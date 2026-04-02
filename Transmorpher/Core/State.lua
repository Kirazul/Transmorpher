local addon, ns = ...

-- ============================================================
-- TRANSMORPHER STATE MANAGER
-- Settings accessor, form detection, slot helpers,
-- dressing room sync, and UI state restoration
-- ============================================================

local _, raceFileName = UnitRace("player")
local _, classFileName = UnitClass("player")
local sex = UnitSex("player")

-- Expose player info to other modules
ns.playerRace = raceFileName
ns.playerClass = classFileName
ns.playerSex = sex

-- Track recently un-morphed slots for network injection
ns.RecentlyUnmorphed = {}
function ns.TrackUnmorphedSlot(equipSlotId, nativeItemId)
    ns.RecentlyUnmorphed[equipSlotId] = nativeItemId or 0
end

-- ============================================================
-- SETTINGS ACCESSOR
-- ============================================================

function ns.GetSettings()
    if not TransmorpherSettingsPerChar then
        TransmorpherSettingsPerChar = {}
    end

    -- Populate defaults
    for k, v in pairs(ns.defaultSettings) do
        if TransmorpherSettingsPerChar[k] == nil then
            if type(v) == "table" then
                local newTable = {}
                for subK, subV in pairs(v) do newTable[subK] = subV end
                TransmorpherSettingsPerChar[k] = newTable
            else
                TransmorpherSettingsPerChar[k] = v
            end
        end
    end

    -- Ensure complex tables are initialized
    if not TransmorpherSettingsPerChar.dressingRoomBackgroundTexture then
        TransmorpherSettingsPerChar.dressingRoomBackgroundTexture = {}
    end

    return TransmorpherSettingsPerChar
end

-- ============================================================
-- MORPH SUSPENSION FLAGS
-- ============================================================
ns.morphSuspended = false
ns.vehicleSuspended = false
ns.dbwSuspended = false
ns.savedMountDisplayForVehicle = nil
ns.wasInVehicleLastFrame = false

-- ============================================================
-- FORM DETECTION
-- ============================================================

function ns.IsModelChangingForm()
    local settings = ns.GetSettings()

    -- Warlock Metamorphosis (highest priority)
    if classFileName == "WARLOCK" and settings.showMetamorphosis then
        local form = GetShapeshiftForm()
        if form > 0 then return true end
    end

    -- If user wants morph in shapeshift, never suspend
    if settings.morphInShapeshift then return false end

    local form = GetShapeshiftForm()
    if form == 0 then return false end

    -- Only druid forms change the model in conflicting ways
    if classFileName == "DRUID" then
        return true
    end

    return false
end

function ns.IsInVehicle()
    return UnitInVehicle("player")
end

function ns.HasDBWProc()
    if not ns.dbwProcIds then return false end
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        if ns.dbwProcIds[spellID] then
            return true
        end
    end
    return false
end

-- ============================================================
-- FORM DEFINITIONS (GROUPED)
-- ============================================================
-- Map specific spell IDs to a "Form Group"
ns.spellToFormGroup = {
    -- Druid
    [5487] = "Bear", [9634] = "Bear",
    [768] = "Cat",
    [24858] = "Moonkin",
    [33891] = "Tree",
    [783] = "Travel",
    [1066] = "Aquatic",
    [33943] = "Flight", [40120] = "Flight",
    -- Shaman
    [2645] = "GhostWolf",
    -- Warlock
    [47241] = "Metamorphosis",
    -- Priest
    [15473] = "Shadowform",
    -- DBW
    [71484] = "DBW_Taunka", [71561] = "DBW_Taunka", [71486] = "DBW_Taunka", [71558] = "DBW_Taunka",
    [71485] = "DBW_Vrykul", [71556] = "DBW_Vrykul", [71492] = "DBW_Vrykul", [71560] = "DBW_Vrykul",
    [71491] = "DBW_IronDwarf", [71559] = "DBW_IronDwarf", [71487] = "DBW_IronDwarf", [71557] = "DBW_IronDwarf",
}

-- Display info for each group
ns.formGroupDB = {
    ["Bear"] = {name="Bear Form", icon="Interface\\Icons\\Ability_Racial_BearForm"},
    ["Cat"] = {name="Cat Form", icon="Interface\\Icons\\Ability_Druid_CatForm"},
    ["Moonkin"] = {name="Moonkin Form", icon="Interface\\Icons\\Spell_Nature_ForceOfNature"},
    ["Tree"] = {name="Tree of Life", icon="Interface\\Icons\\Ability_Druid_TreeofLife"},
    ["Travel"] = {name="Travel Form", icon="Interface\\Icons\\Ability_Druid_TravelForm"},
    ["Aquatic"] = {name="Aquatic Form", icon="Interface\\Icons\\Ability_Druid_AquaticForm"},
    ["Flight"] = {name="Flight Form", icon="Interface\\Icons\\Ability_Druid_FlightForm"},
    ["GhostWolf"] = {name="Ghost Wolf", icon="Interface\\Icons\\Spell_Nature_SpiritWolf"},
    ["Metamorphosis"] = {name="Metamorphosis", icon="Interface\\Icons\\Spell_Shadow_DemonForm"},
    ["Shadowform"] = {name="Shadowform", icon="Interface\\Icons\\Spell_Shadow_Shadowform"},
    ["DBW_Taunka"] = {name="Taunka (DBW)", icon=ns.GetSpellIcon(71484)},
    ["DBW_Vrykul"] = {name="Vrykul (DBW)", icon=ns.GetSpellIcon(71485)},
    ["DBW_IronDwarf"] = {name="Iron Dwarf (DBW)", icon=ns.GetSpellIcon(71491)},
}

-- Order for UI
ns.orderedFormGroups = {
    "Bear", "Cat", "Moonkin", "Tree", "Travel", "Aquatic", "Flight",
    "GhostWolf", "Metamorphosis", "Shadowform",
    "DBW_Taunka", "DBW_Vrykul", "DBW_IronDwarf"
}

-- ============================================================
-- FORM MORPH HELPERS
-- ============================================================

function ns.GetFormMorph(groupID)
    if not TransmorpherCharacterState or not TransmorpherCharacterState.Forms then return nil end
    local forms = TransmorpherCharacterState.Forms
    local direct = forms[groupID]
    if direct then return direct end
    if type(groupID) ~= "string" then return nil end
    if not ns.spellToFormGroup then return nil end
    for spellID, mappedGroup in pairs(ns.spellToFormGroup) do
        if mappedGroup == groupID then
            local legacy = forms[spellID]
            if legacy then return legacy end
        end
    end
    return nil
end

function ns.SetFormMorph(groupID, displayID)
    if not TransmorpherCharacterState then return end
    if not TransmorpherCharacterState.Forms then TransmorpherCharacterState.Forms = {} end
    if displayID and displayID > 0 then
        TransmorpherCharacterState.Forms[groupID] = displayID
    else
        TransmorpherCharacterState.Forms[groupID] = nil
    end
    if type(groupID) == "string" and ns.spellToFormGroup then
        for spellID, mappedGroup in pairs(ns.spellToFormGroup) do
            if mappedGroup == groupID then
                TransmorpherCharacterState.Forms[spellID] = nil
            end
        end
    end
end

ns.runtimeSpellMorphs = ns.runtimeSpellMorphs or {}

-- Character-specific runtime morphs to prevent cross-character leakage
local function GetRuntimeMorphsTable()
    if not ns.runtimeSpellMorphs then
        ns.runtimeSpellMorphs = {}
    end
    return ns.runtimeSpellMorphs
end

function ns.GetBaseSpellMorph(sourceSpellId)
    if not TransmorpherCharacterState or not TransmorpherCharacterState.SpellMorphs then return nil end
    local key = tonumber(sourceSpellId)
    if not key then return nil end
    local target = tonumber(TransmorpherCharacterState.SpellMorphs[key])
    if target and target > 0 then
        return target
    end
    return nil
end

function ns.GetSpellMorph(sourceSpellId)
    local key = tonumber(sourceSpellId)
    if not key then return nil end

    -- Priority 1: Runtime morphs - highest precedence
    local runtimeTable = GetRuntimeMorphsTable()
    local runtimeTarget = tonumber(runtimeTable[key])
    if runtimeTarget and runtimeTarget > 0 then
        return runtimeTarget
    end

    -- Priority 2: Base morphs (saved spell morphs)
    return ns.GetBaseSpellMorph(key)
end

function ns.SetSpellMorph(sourceSpellId, targetSpellId)
    if not TransmorpherCharacterState then return end
    if not TransmorpherCharacterState.SpellMorphs then TransmorpherCharacterState.SpellMorphs = {} end
    local source = tonumber(sourceSpellId)
    local target = tonumber(targetSpellId)
    if not source or source <= 0 then return end
    if target and target > 0 then
        TransmorpherCharacterState.SpellMorphs[source] = target
    else
        TransmorpherCharacterState.SpellMorphs[source] = nil
    end
end

function ns.SetRuntimeSpellMorph(sourceSpellId, targetSpellId)
    local source = tonumber(sourceSpellId)
    local target = tonumber(targetSpellId)
    if not source or source <= 0 then return end
    if target and target > 0 then
        ns.runtimeSpellMorphs[source] = target
    else
        ns.runtimeSpellMorphs[source] = nil
    end
end

function ns.ClearRuntimeSpellMorph(sourceSpellId)
    local source = tonumber(sourceSpellId)
    if not source or source <= 0 then return end
    ns.runtimeSpellMorphs[source] = nil
end

function ns.ClearAllRuntimeSpellMorphs()
    wipe(ns.runtimeSpellMorphs)
end

function ns.GetEffectiveSpellMorphPairs()
    local combined = {}

    -- First add base morphs (lower priority)
    if TransmorpherCharacterState and TransmorpherCharacterState.SpellMorphs then
        for sourceSpellId, targetSpellId in pairs(TransmorpherCharacterState.SpellMorphs) do
            local source = tonumber(sourceSpellId)
            local target = tonumber(targetSpellId)
            if source and source > 0 and target and target > 0 then
                combined[source] = target
            end
        end
    end

    -- Then override with runtime morphs (higher priority)
    local runtimeTable = GetRuntimeMorphsTable()
    for sourceSpellId, targetSpellId in pairs(runtimeTable) do
        local source = tonumber(sourceSpellId)
        local target = tonumber(targetSpellId)
        if source and source > 0 and target and target > 0 then
            combined[source] = target
        end
    end

    return combined
end

-- ============================================================
-- EQUIPPED ITEM HELPER
-- ============================================================

function ns.GetEquippedItemForSlot(slotName)
    local csn = slotName
    if csn == ns.mainHandSlot then csn = "MainHand" end
    if csn == ns.offHandSlot  then csn = "SecondaryHand" end
    if csn == ns.rangedSlot   then csn = "Ranged" end
    if csn == ns.backSlot     then csn = "Back" end
    local slotId = GetInventorySlotInfo(csn .. "Slot")
    if not slotId then return nil end
    return GetInventoryItemID("player", slotId)
end

-- ============================================================
-- SPECIAL SLOTS UPDATE
-- Updates Mount, Pet, Combat Pet, and Morph Form preview slots
-- ============================================================

function ns.UpdateSpecialSlots()
    local mainFrame = ns.mainFrame
    if not mainFrame or not mainFrame.specialSlots then return end

    -- Helper to update a mount slot from a display ID
    local function UpdateMountSlot(slotKey, displayID, slotLabel, glowColor)
        local mountSlot = mainFrame.specialSlots[slotKey]
        if not mountSlot then return end

        -- Handle hidden mount (-1)
        if displayID and displayID == -1 then
            mountSlot.displayID = -1
            mountSlot.spellID = nil
            mountSlot.name = slotLabel .. ": Hidden"
            mountSlot.icon:SetTexture("Interface\\Icons\\Spell_Nature_Invisibilty")
            mountSlot.icon:SetVertexColor(0.6, 0.6, 0.6, 0.8)
            mountSlot.icon:Show()
            ns.ShowMorphGlow(mountSlot, "red")
            return
        end

        if displayID and displayID > 0 then
            local mountEntry = nil
            for _, entry in ipairs(ns.mountsDB or {}) do
                if entry[3] == displayID then
                    mountEntry = entry
                    break
                end
            end
            if mountEntry then
                mountSlot.displayID = mountEntry[3]
                mountSlot.spellID = mountEntry[2]
                mountSlot.name = mountEntry[1]
                mountSlot.icon:SetTexture(ns.GetSpellIcon(mountEntry[2]))
                mountSlot.icon:SetVertexColor(1, 1, 1, 1)
                mountSlot.icon:Show()
                ns.ShowMorphGlow(mountSlot, glowColor)
            else
                mountSlot.displayID = displayID
                mountSlot.spellID = nil
                mountSlot.name = "ID " .. displayID
                mountSlot.icon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
                mountSlot.icon:SetVertexColor(1, 1, 1, 1)
                mountSlot.icon:Show()
                ns.ShowMorphGlow(mountSlot, glowColor)
            end
        else
            mountSlot.displayID = nil
            mountSlot.spellID = nil
            mountSlot.name = nil
            mountSlot.icon:Hide()
            ns.HideMorphGlow(mountSlot)
        end
    end

    -- Single Mount slot
    local mountDisplay = TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay
    UpdateMountSlot("Mount", mountDisplay, "Mount", "red")

    -- Pet slot
    if mainFrame.specialSlots.Pet then
        local petSlot = mainFrame.specialSlots.Pet
        if TransmorpherCharacterState and TransmorpherCharacterState.PetDisplay then
            local petEntry = nil
            for _, entry in ipairs(ns.petsDB or {}) do
                if entry[3] == TransmorpherCharacterState.PetDisplay then
                    petEntry = entry
                    break
                end
            end
            if petEntry then
                petSlot.displayID = petEntry[3]
                petSlot.spellID = petEntry[2]
                petSlot.name = petEntry[1]
                petSlot.icon:SetTexture(ns.GetSpellIcon(petEntry[2]))
                petSlot.icon:Show()
                ns.ShowMorphGlow(petSlot, "red")
            else
                petSlot.displayID = nil
                petSlot.spellID = nil
                petSlot.name = nil
                petSlot.icon:Hide()
                ns.HideMorphGlow(petSlot)
            end
        else
            petSlot.displayID = nil
            petSlot.spellID = nil
            petSlot.name = nil
            petSlot.icon:Hide()
            ns.HideMorphGlow(petSlot)
        end
    end

    -- Combat Pet slot
    if mainFrame.specialSlots.CombatPet then
        local combatPetSlot = mainFrame.specialSlots.CombatPet
        if TransmorpherCharacterState and TransmorpherCharacterState.HunterPetDisplay then
            local combatPetEntry = nil
            for _, entry in ipairs(ns.combatPetsDB or {}) do
                if entry[3] == TransmorpherCharacterState.HunterPetDisplay then
                    combatPetEntry = entry
                    break
                end
            end
            combatPetSlot.displayID = TransmorpherCharacterState.HunterPetDisplay
            combatPetSlot.name = combatPetEntry and combatPetEntry[1] or ("Display ID: " .. TransmorpherCharacterState.HunterPetDisplay)
            local iconPath = combatPetEntry and ns.GetCombatPetIcon(combatPetEntry[2]) or "Interface\\Icons\\Ability_Hunter_BeastCall"
            combatPetSlot.icon:SetTexture(iconPath)
            combatPetSlot.icon:Show()
            ns.ShowMorphGlow(combatPetSlot, "red")
        else
            combatPetSlot.displayID = nil
            combatPetSlot.name = nil
            combatPetSlot.icon:Hide()
            ns.HideMorphGlow(combatPetSlot)
        end
    end

    -- Morph Form slot
    if mainFrame.specialSlots.MorphForm then
        local morphFormSlot = mainFrame.specialSlots.MorphForm
        if TransmorpherCharacterState and TransmorpherCharacterState.Morph then
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

            local iconPath = "Interface\\Icons\\Spell_Shadow_Charm"
            if morphEntry and morphEntry.name then
                local nameLower = morphEntry.name:lower()
                local raceIcons = {
                    { "human",    "Achievement_Character_Human_Male" },
                    { "orc",      "Achievement_Character_Orc_Male" },
                    { "dwarf",    "Achievement_Character_Dwarf_Male" },
                    { "nightelf", "Achievement_Character_Nightelf_Male" },
                    { "night elf","Achievement_Character_Nightelf_Male" },
                    { "undead",   "Achievement_Character_Undead_Male" },
                    { "scourge",  "Achievement_Character_Undead_Male" },
                    { "tauren",   "Achievement_Character_Tauren_Male" },
                    { "gnome",    "Achievement_Character_Gnome_Male" },
                    { "troll",    "Achievement_Character_Troll_Male" },
                    { "bloodelf", "Achievement_Character_Bloodelf_Male" },
                    { "blood elf","Achievement_Character_Bloodelf_Male" },
                    { "draenei",  "Achievement_Character_Draenei_Male" },
                }
                for _, pair in ipairs(raceIcons) do
                    if nameLower:find(pair[1]) then
                        iconPath = "Interface\\Icons\\" .. pair[2]
                        break
                    end
                end
            end

            morphFormSlot.icon:SetTexture(iconPath)
            morphFormSlot.icon:Show()
            ns.ShowMorphGlow(morphFormSlot, "purple")
        else
            morphFormSlot.displayID = nil
            morphFormSlot.name = nil
            morphFormSlot.icon:Hide()
            ns.HideMorphGlow(morphFormSlot)
        end
    end
end

-- ============================================================
-- DRESSING ROOM SYNC
-- Rebuilds the 3D preview model from all current slot items
-- ============================================================

-- Debounced sync scheduler to coalesce multiple rebuild requests
function ns.ScheduleDressingRoomSync(delay)
    local d = (type(delay) == "number" and delay >= 0) and delay or 0.05
    if ns._dressingRoomSyncScheduled then return end
    ns._dressingRoomSyncScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(d, function()
            ns._dressingRoomSyncScheduled = false
            if ns.SyncDressingRoom then ns.SyncDressingRoom() end
        end)
    else
        if not ns._drSyncFrame then
            ns._drSyncFrame = CreateFrame("Frame"); ns._drSyncFrame:Hide(); ns._drSyncFrame.elapsed = 0
        end
        ns._drSyncFrame.elapsed = 0
        ns._drSyncFrame:SetScript("OnUpdate", function(self, dt)
            self.elapsed = self.elapsed + dt
            if self.elapsed < d then return end
            self:Hide(); self:SetScript("OnUpdate", nil)
            ns._dressingRoomSyncScheduled = false
            if ns.SyncDressingRoom then ns.SyncDressingRoom() end
        end)
        ns._drSyncFrame:Show()
    end
end

function ns.SyncDressingRoom()
    local mainFrame = ns.mainFrame
    if not mainFrame or not mainFrame.dressingRoom or not mainFrame.slots then return end
    ns._dressingRoomSyncToken = (ns._dressingRoomSyncToken or 0) + 1
    local syncToken = ns._dressingRoomSyncToken
    mainFrame.dressingRoom:SetLight(1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64)
    mainFrame.dressingRoom:SetModelAlpha(0)
    mainFrame.dressingRoom:Undress()

    local hasMainHand = mainFrame.slots["Main Hand"] and mainFrame.slots["Main Hand"].itemId
        and mainFrame.slots["Main Hand"].itemId > 0 and not mainFrame.slots["Main Hand"].isHiddenSlot
    local hasOffHand = mainFrame.slots["Off-hand"] and mainFrame.slots["Off-hand"].itemId
        and mainFrame.slots["Off-hand"].itemId > 0 and not mainFrame.slots["Off-hand"].isHiddenSlot
    local pendingAsync = 0
    local revealed = false
    local function Reveal()
        if revealed then return end
        revealed = true
        if ns._dressingRoomSyncToken ~= syncToken then return end
        if not mainFrame or not mainFrame.dressingRoom then return end
        mainFrame.dressingRoom:SetModelAlpha(1)
    end

    for _, slotName in ipairs(ns.slotOrder) do
        local slot = mainFrame.slots[slotName]
        if slot and slot.itemId and slot.itemId > 0 and not slot.isHiddenSlot then
            if slotName == "Ranged" and (hasMainHand or hasOffHand) then
                -- Don't display ranged weapon when melee weapons are equipped
            else
                do
                    local expectedId = slot.itemId
                    local slotRef = slot
                    mainFrame.dressingRoom:TryOn(expectedId)
                    pendingAsync = pendingAsync + 1
                    ns.QueryItem(expectedId, function(queriedItemId, success)
                        if ns._dressingRoomSyncToken == syncToken then
                            if success and queriedItemId == expectedId and slotRef and slotRef.itemId == expectedId and mainFrame and mainFrame.dressingRoom then
                                mainFrame.dressingRoom:TryOn(queriedItemId)
                            end
                            pendingAsync = pendingAsync - 1
                            if pendingAsync <= 0 then
                                Reveal()
                            end
                        end
                    end)
                end
            end
        end
    end

    ns.UpdateSpecialSlots()
    if pendingAsync <= 0 then
        Reveal()
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.12, Reveal)
    end
end

-- ============================================================
-- RESTORE MORPHED UI
-- Called once after PLAYER_LOGIN when persistence is active.
-- Populates every slot with real equipped items first, then
-- overlays morphed items with golden glow.
-- ============================================================

function ns.RestoreMorphedUI()
    local settings = ns.GetSettings()
    if not settings.saveMorphState then return end
    if not TransmorpherCharacterState then return end

    local mainFrame = ns.mainFrame
    local restoreFrame = CreateFrame("Frame")
    restoreFrame.elapsed = 0
    restoreFrame:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < 0.6 then return end
        self:Hide()
        self:SetScript("OnUpdate", nil)

        if not mainFrame or not mainFrame.slots then return end

        -- Step 1: populate every slot with real equipped item (no glow)
        for _, slotName in pairs(ns.slotOrder) do
            local slot = mainFrame.slots[slotName]
            if slot then
                if slotName == ns.rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(classFileName) then
                    slot:RemoveItem()
                else
                    local equippedId = ns.GetEquippedItemForSlot(slotName)
                    if equippedId then
                        slot:SetItem(equippedId)
                    else
                        slot:RemoveItem()
                    end
                end
                slot.isMorphed = false
                slot.morphedItemId = nil
                ns.HideMorphGlow(slot)
            end
        end

        -- Step 2: overlay morphed items with glow
        if TransmorpherCharacterState.Items then
            for equipSlotId, itemId in pairs(TransmorpherCharacterState.Items) do
                local slotName = ns.equipSlotIdToSlot[equipSlotId]
                if slotName and mainFrame.slots[slotName] then
                    local equippedId = ns.GetEquippedItemForSlot(slotName)
                    local slot = mainFrame.slots[slotName]
                    local isHidden = itemId == -1 or (TransmorpherCharacterState.HiddenItems and TransmorpherCharacterState.HiddenItems[equipSlotId])
                    if isHidden then
                        local iconItemId = nil
                        local trackedItem = TransmorpherCharacterState.Items and TransmorpherCharacterState.Items[equipSlotId]
                        if trackedItem and trackedItem > 0 then
                            iconItemId = trackedItem
                        elseif slot.itemId and slot.itemId > 0 then
                            iconItemId = slot.itemId
                        else
                            iconItemId = ns.GetEquippedItemForSlot(slotName)
                        end
                        if iconItemId and iconItemId > 0 then
                            slot:SetItem(iconItemId)
                        end
                        if slot.textures and slot.textures.item and slot.textures.empty and slot.itemId and slot.itemId > 0 then
                            slot.textures.empty:Hide()
                            slot.textures.item:Show()
                        end
                        slot.isHiddenSlot = true
                        slot.isMorphed = true
                        slot.morphedItemId = iconItemId and iconItemId > 0 and iconItemId or nil
                        ns.ShowMorphGlow(slot)
                        if slot.eyeButton then
                            slot.eyeButton.isHidden = true
                            if slot.eyeButton.UpdateVisuals then slot.eyeButton:UpdateVisuals() end
                        end
                    elseif not (equippedId and equippedId == itemId) then
                        slot:SetItem(itemId)
                        slot.isHiddenSlot = false
                        slot.isMorphed = true
                        slot.morphedItemId = itemId
                        ns.ShowMorphGlow(slot)
                        if slot.eyeButton then
                            slot.eyeButton.isHidden = false
                            if slot.eyeButton.UpdateVisuals then slot.eyeButton:UpdateVisuals() end
                        end
                    else
                        slot.isHiddenSlot = false
                        if slot.eyeButton then
                            slot.eyeButton.isHidden = false
                            if slot.eyeButton.UpdateVisuals then slot.eyeButton:UpdateVisuals() end
                        end
                    end
                end
            end
        end
        if TransmorpherCharacterState.HiddenItems then
            for equipSlotId, hidden in pairs(TransmorpherCharacterState.HiddenItems) do
                if hidden then
                    local slotName = ns.equipSlotIdToSlot[equipSlotId]
                    local slot = slotName and mainFrame.slots[slotName]
                    if slot then
                        local iconItemId = nil
                        local trackedItem = TransmorpherCharacterState.Items and TransmorpherCharacterState.Items[equipSlotId]
                        if trackedItem and trackedItem > 0 then
                            iconItemId = trackedItem
                        elseif slot.itemId and slot.itemId > 0 then
                            iconItemId = slot.itemId
                        else
                            iconItemId = ns.GetEquippedItemForSlot(slotName)
                        end
                        if iconItemId and iconItemId > 0 then
                            slot:SetItem(iconItemId)
                        end
                        if slot.textures and slot.textures.item and slot.textures.empty and slot.itemId and slot.itemId > 0 then
                            slot.textures.empty:Hide()
                            slot.textures.item:Show()
                        end
                        slot.isHiddenSlot = true
                        slot.isMorphed = true
                        slot.morphedItemId = iconItemId and iconItemId > 0 and iconItemId or nil
                        ns.ShowMorphGlow(slot)
                        if slot.eyeButton then
                            slot.eyeButton.isHidden = true
                            if slot.eyeButton.UpdateVisuals then slot.eyeButton:UpdateVisuals() end
                        end
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
                ns.ShowMorphGlow(es, "orange")
            end
            if TransmorpherCharacterState.EnchantOH then
                local eid = TransmorpherCharacterState.EnchantOH
                local eName = tostring(eid)
                if ns.enchantDB and ns.enchantDB[eid] then eName = ns.enchantDB[eid] end
                local es = mainFrame.enchantSlots["Enchant OH"]
                es:SetEnchant(eid, eName)
                es.isMorphed = true
                ns.ShowMorphGlow(es, "orange")
            end
        end

        ns.SyncDressingRoom()
    end)
end
