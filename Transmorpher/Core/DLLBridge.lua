local addon, ns = ...

-- ============================================================
-- TRANSMORPHER DLL BRIDGE
-- Communication with the Transmorpher C++ DLL via global
-- variables. The DLL polls TRANSMORPHER_CMD every ~20ms.
-- ============================================================

-- Global variables the DLL interacts with
TRANSMORPHER_CMD = ""             -- DLL reads this for commands
TRANSMORPHER_DLL_LOADED = nil     -- DLL sets to "TRUE" when loaded

-- ============================================================
-- COMMAND TRACKING
-- Persist morph commands into TransmorpherCharacterState so
-- they survive /reload and character logout.
-- ============================================================

local function InitCharacterState()
    if not TransmorpherCharacterState then
        TransmorpherCharacterState = {
            Items = {},
            Morph = nil,
            Scale = nil,
            MountDisplay = nil,
            PetDisplay = nil,
            Mounts = {}, -- Per-mount morphs: [spellID] = displayID
            MountHidden = false, -- Toggle for mount invisibility
            HunterPetDisplay = nil,
            HunterPetScale = nil,
            EnchantMH = nil,
            EnchantOH = nil,
            TitleID = nil,
            WeaponSets = {},
            Forms = {},
            SpellMorphs = {},
            HiddenItems = {}, -- [slotId] = true
        }
    end
    if not TransmorpherCharacterState.Items then TransmorpherCharacterState.Items = {} end
    if not TransmorpherCharacterState.HiddenItems then TransmorpherCharacterState.HiddenItems = {} end
    if not TransmorpherCharacterState.Mounts then TransmorpherCharacterState.Mounts = {} end
    if not TransmorpherCharacterState.WeaponSets then TransmorpherCharacterState.WeaponSets = {} end
    if not TransmorpherCharacterState.SpellMorphs then TransmorpherCharacterState.SpellMorphs = {} end
end

-- Helper: get weapon set key from equipped weapons
local function GetWeaponSetKey()
    local mainHand = GetInventoryItemLink("player", 16) or "0"
    local offHand  = GetInventoryItemLink("player", 17) or "0"
    return mainHand .. "|" .. offHand
end
ns.GetWeaponSetKey = GetWeaponSetKey

local function TrackMorphCommand(cmd)
    local settings = ns.GetSettings()
    if not settings.saveMorphState then return end
    InitCharacterState()

    for singleCmd in cmd:gmatch("[^|]+") do
        local parts = {strsplit(":", singleCmd)}
        local prefix = parts[1]

        if prefix == "ITEM" and parts[2] and parts[3] then
            local slotId = tonumber(parts[2])
            local itemId = tonumber(parts[3])
            if slotId then
                if itemId == -1 then
                    TransmorpherCharacterState.HiddenItems[slotId] = true
                    if TransmorpherCharacterState.Items[slotId] == nil then
                        TransmorpherCharacterState.Items[slotId] = -1
                    end
                else
                    TransmorpherCharacterState.Items[slotId] = itemId
                    TransmorpherCharacterState.HiddenItems[slotId] = nil
                end
            end

        elseif prefix == "MORPH" and parts[2] then
            local val = tonumber(parts[2])
            TransmorpherCharacterState.Morph = (val and val > 0) and val or nil

        elseif prefix == "SCALE" and parts[2] then
            TransmorpherCharacterState.Scale = tonumber(parts[2])

        elseif prefix == "MOUNT_MORPH" and parts[2] then
            local mountMorphID = tonumber(parts[2])
            if settings.saveMountMorph then
                if mountMorphID and mountMorphID > 0 then
                    TransmorpherCharacterState.MountHidden = false
                    TransmorpherCharacterState.MountDisplay = mountMorphID
                end
            end
        elseif prefix == "MOUNT_RESET" then
            TransmorpherCharacterState.MountDisplay = nil
            TransmorpherCharacterState.GroundMountDisplay = nil
            TransmorpherCharacterState.GroundMountName = nil
            TransmorpherCharacterState.FlyingMountDisplay = nil
            TransmorpherCharacterState.FlyingMountName = nil
            TransmorpherCharacterState.MountHidden = false
            if TransmorpherCharacterState.Mounts then
                wipe(TransmorpherCharacterState.Mounts)
            end
            ns.networkResetPending = true

        elseif prefix == "PET_MORPH" and parts[2] then
            if settings.savePetMorph then
                TransmorpherCharacterState.PetDisplay = tonumber(parts[2])
            end
        elseif prefix == "PET_RESET" then
            TransmorpherCharacterState.PetDisplay = nil
            ns.networkResetPending = true

        elseif prefix == "HPET_MORPH" and parts[2] then
            if settings.saveCombatPetMorph or settings.saveHunterPetMorph then
                TransmorpherCharacterState.HunterPetDisplay = tonumber(parts[2])
            end
        elseif prefix == "HPET_SCALE" and parts[2] then
            if settings.saveCombatPetMorph or settings.saveHunterPetMorph then
                TransmorpherCharacterState.HunterPetScale = tonumber(parts[2])
            end
        elseif prefix == "HPET_RESET" then
            TransmorpherCharacterState.HunterPetDisplay = nil
            TransmorpherCharacterState.HunterPetScale = nil
            ns.networkResetPending = true

        elseif prefix == "ENCHANT_MH" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then TransmorpherCharacterState.EnchantMH = val end
        elseif prefix == "ENCHANT_OH" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then TransmorpherCharacterState.EnchantOH = val end
        elseif prefix == "ENCHANT_RESET_MH" then
            TransmorpherCharacterState.EnchantMH = nil
            ns.networkResetPending = true
        elseif prefix == "ENCHANT_RESET_OH" then
            TransmorpherCharacterState.EnchantOH = nil
            ns.networkResetPending = true
        elseif prefix == "ENCHANT_RESET" then
            TransmorpherCharacterState.EnchantMH = nil
            TransmorpherCharacterState.EnchantOH = nil
            ns.networkResetPending = true

        elseif prefix == "TITLE" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then TransmorpherCharacterState.TitleID = val end
        elseif prefix == "TITLE_RESET" then
            TransmorpherCharacterState.TitleID = nil
            ns.networkResetPending = true
        elseif prefix == "SPELL_MORPH" and parts[2] and parts[3] then
            local sourceSpellId = tonumber(parts[2])
            local targetSpellId = tonumber(parts[3])
            if sourceSpellId and sourceSpellId > 0 then
                if not TransmorpherCharacterState.SpellMorphs then TransmorpherCharacterState.SpellMorphs = {} end
                if targetSpellId and targetSpellId > 0 then
                    TransmorpherCharacterState.SpellMorphs[sourceSpellId] = targetSpellId
                else
                    TransmorpherCharacterState.SpellMorphs[sourceSpellId] = nil
                end
            end
        elseif prefix == "SPELL_RESET" and parts[2] then
            local sourceSpellId = tonumber(parts[2])
            if sourceSpellId and sourceSpellId > 0 and TransmorpherCharacterState.SpellMorphs then
                TransmorpherCharacterState.SpellMorphs[sourceSpellId] = nil
            end
        elseif prefix == "SPELL_RESET_ALL" then
            if TransmorpherCharacterState.SpellMorphs then
                wipe(TransmorpherCharacterState.SpellMorphs)
            else
                TransmorpherCharacterState.SpellMorphs = {}
            end

        elseif prefix == "RESET" and parts[2] then
            if parts[2] == "ALL" then
                if TransmorpherCharacterState and TransmorpherCharacterState.Items then
                    for slotId, _ in pairs(TransmorpherCharacterState.Items) do
                        local slotName = ns.equipSlotIdToSlot[slotId]
                        if slotName then
                            local nativeId = ns.GetEquippedItemForSlot(slotName) or 0
                            ns.TrackUnmorphedSlot(slotId, nativeId)
                        end
                    end
                end
                ns.networkResetPending = true
                -- Clear state in-place to preserve references
                if TransmorpherCharacterState.Items then
                    wipe(TransmorpherCharacterState.Items)
                else
                    TransmorpherCharacterState.Items = {}
                end
                TransmorpherCharacterState.Morph = nil
                TransmorpherCharacterState.Scale = nil
                TransmorpherCharacterState.MountDisplay = nil
                TransmorpherCharacterState.PetDisplay = nil
                TransmorpherCharacterState.MountHidden = false
                if TransmorpherCharacterState.HiddenItems then
                    wipe(TransmorpherCharacterState.HiddenItems)
                else
                    TransmorpherCharacterState.HiddenItems = {}
                end
                TransmorpherCharacterState.GroundMountDisplay = nil
                TransmorpherCharacterState.GroundMountName = nil
                TransmorpherCharacterState.FlyingMountDisplay = nil
                TransmorpherCharacterState.FlyingMountName = nil
                -- Clear per-mount morphs too
                if TransmorpherCharacterState.Mounts then
                    wipe(TransmorpherCharacterState.Mounts)
                else
                    TransmorpherCharacterState.Mounts = {}
                end
                TransmorpherCharacterState.HunterPetDisplay = nil
                TransmorpherCharacterState.HunterPetScale = nil
                TransmorpherCharacterState.EnchantMH = nil
                TransmorpherCharacterState.EnchantOH = nil
                TransmorpherCharacterState.TitleID = nil
                if TransmorpherCharacterState.WeaponSets then
                    wipe(TransmorpherCharacterState.WeaponSets)
                else
                    TransmorpherCharacterState.WeaponSets = {}
                end
                -- Preserve Forms
                if not TransmorpherCharacterState.Forms then TransmorpherCharacterState.Forms = {} end
                if not TransmorpherCharacterState.SpellMorphs then TransmorpherCharacterState.SpellMorphs = {} end
            else
                local slotId = tonumber(parts[2])
                if slotId then
                    TransmorpherCharacterState.Items[slotId] = nil
                    if TransmorpherCharacterState.HiddenItems then
                        TransmorpherCharacterState.HiddenItems[slotId] = nil
                    end
                    if slotId == 16 or slotId == 17 then
                        local setKey = GetWeaponSetKey()
                        if TransmorpherCharacterState.WeaponSets and TransmorpherCharacterState.WeaponSets[setKey] then
                            TransmorpherCharacterState.WeaponSets[setKey][slotId] = nil
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================
-- LOW-LEVEL COMMAND TRANSPORT
-- ============================================================

local function AppendCommand(cmd)
    if TRANSMORPHER_CMD == "" then
        TRANSMORPHER_CMD = cmd
    else
        TRANSMORPHER_CMD = TRANSMORPHER_CMD .. "|" .. cmd
    end
end

local morphBatchDepth = 0
local morphBatchStatusDirty = false

function ns.BeginMorphBatch()
    morphBatchDepth = morphBatchDepth + 1
end

function ns.EndMorphBatch()
    if morphBatchDepth <= 0 then return end
    morphBatchDepth = morphBatchDepth - 1
    if morphBatchDepth == 0 and morphBatchStatusDirty then
        morphBatchStatusDirty = false
        if ns.UpdateMorphStatusBar then ns.UpdateMorphStatusBar() end
    end
end

-- Send a morph command (tracked in SavedVariables)
function ns.SendMorphCommand(cmd)
    TrackMorphCommand(cmd)
    AppendCommand(cmd)

    if morphBatchDepth > 0 then
        morphBatchStatusDirty = true
    else
        if ns.UpdateMorphStatusBar then ns.UpdateMorphStatusBar() end
    end

    -- Sync with other players
    if ns.BroadcastMorphState then
        ns.BroadcastMorphState()
    end
end

-- Send a raw signal to the DLL (SUSPEND/RESUME) without tracking state
function ns.SendRawMorphCommand(cmd)
    AppendCommand(cmd)
end

-- ============================================================
-- DLL STATUS
-- ============================================================

-- Track if DLL settings have been initialized
local dllSettingsInitialized = false
local dllInitRetryFrame = CreateFrame("Frame")
dllInitRetryFrame:Hide()
dllInitRetryFrame.elapsed = 0
dllInitRetryFrame.startedAt = 0
dllInitRetryFrame:SetScript("OnUpdate", function(self, elapsed)
    if dllSettingsInitialized then
        self:Hide()
        return
    end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    if TRANSMORPHER_DLL_LOADED then
        ns.InitializeDLLSettings()
        if dllSettingsInitialized then
            self:Hide()
        end
        return
    end
    if self.startedAt > 0 and (GetTime() - self.startedAt) > 60 then
        self:Hide()
    end
end)

function ns.IsMorpherReady()
    if TRANSMORPHER_DLL_LOADED then
        return true
    else
        return false
    end
end

-- Initialize DLL settings (called once when DLL is first detected)
function ns.InitializeDLLSettings()
    if dllSettingsInitialized then return end
    if not TRANSMORPHER_DLL_LOADED then
        if not dllInitRetryFrame:IsShown() then
            dllInitRetryFrame.elapsed = 0
            dllInitRetryFrame.startedAt = GetTime()
            dllInitRetryFrame:Show()
        end
        return
    end
    
    local settings = ns.GetSettings()
    
    if not TransmorpherCharacterState then 
        TransmorpherCharacterState = {} 
    end

    -- STATE RECOVERY: If SavedVariables were wiped, pull from DLL
    local hasItems = next(TransmorpherCharacterState.Items or {}) ~= nil
    local hasMorphData = TransmorpherCharacterState.Morph or hasItems
    
    if TRANSMORPHER_DLL_STATE and not hasMorphData then
        TransmorpherCharacterState.Morph = TRANSMORPHER_DLL_STATE.morph
        TransmorpherCharacterState.Scale = TRANSMORPHER_DLL_STATE.scale
        TransmorpherCharacterState.MountDisplay = TRANSMORPHER_DLL_STATE.mount
        TransmorpherCharacterState.EnchantMH = TRANSMORPHER_DLL_STATE.emh
        TransmorpherCharacterState.EnchantOH = TRANSMORPHER_DLL_STATE.eoh
        TransmorpherCharacterState.TitleID = TRANSMORPHER_DLL_STATE.title
        TransmorpherCharacterState.Items = TransmorpherCharacterState.Items or {}
        TransmorpherCharacterState.HiddenItems = TransmorpherCharacterState.HiddenItems or {}
        TransmorpherCharacterState.SpellMorphs = TransmorpherCharacterState.SpellMorphs or {}
        
        for s, id in pairs(TRANSMORPHER_DLL_STATE.items) do
            if id == 0 then
                TransmorpherCharacterState.HiddenItems[s] = true
            else
                TransmorpherCharacterState.Items[s] = id
            end
        end
        if TRANSMORPHER_DLL_STATE.spells then
            for sourceSpellId, targetSpellId in pairs(TRANSMORPHER_DLL_STATE.spells) do
                local source = tonumber(sourceSpellId)
                local target = tonumber(targetSpellId)
                if source and source > 0 and target and target > 0 then
                    TransmorpherCharacterState.SpellMorphs[source] = target
                end
            end
        end
        
        if ns.RestoreMorphedUI then
            ns.RestoreMorphedUI()
        end
    end

    -- Send all settings to DLL immediately
    ns.SendRawMorphCommand("SET:DBW:" .. (settings.showDBWProc and "1" or "0"))
    ns.SendRawMorphCommand("SET:META:" .. (settings.showMetamorphosis and "1" or "0"))
    ns.SendRawMorphCommand("SET:SHAPE:" .. (settings.morphInShapeshift and "1" or "0"))
    
    dllSettingsInitialized = true
    dllInitRetryFrame:Hide()
    
    -- Sync all saved state to the DLL immediately upon initialization
    if ns.SendFullMorphState then
        ns.SendFullMorphState()
    end

    if type(Log) == "function" then
        Log("DLL settings initialized: DBW=%s, META=%s, SHAPE=%s",
            settings.showDBWProc and "1" or "0",
            settings.showMetamorphosis and "1" or "0",
            settings.morphInShapeshift and "1" or "0")
    end
end

-- Helper: Re-apply pet morphs from saved state
function ns.ApplyPetMorphs()
    local settings = ns.GetSettings()
    if not settings.saveMorphState or not TransmorpherCharacterState then return end

    local cmdQueue = {}
    -- Combat Pet
    if TransmorpherCharacterState.HunterPetDisplay and (settings.saveCombatPetMorph or settings.saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_MORPH:" .. TransmorpherCharacterState.HunterPetDisplay)
    end
    if TransmorpherCharacterState.HunterPetScale and (settings.saveCombatPetMorph or settings.saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_SCALE:" .. TransmorpherCharacterState.HunterPetScale)
    end
    -- Non-combat Pet
    if TransmorpherCharacterState.PetDisplay and settings.savePetMorph then
        table.insert(cmdQueue, "PET_MORPH:" .. TransmorpherCharacterState.PetDisplay)
    end

    if #cmdQueue > 0 then
        ns.SendRawMorphCommand(table.concat(cmdQueue, "|"))
    end
end

-- ============================================================
-- FULL STATE RESTORE
-- Sends all saved morph state to the DLL (used on login/zone change).
-- ============================================================

-- Flag: when true, next SendFullMorphState prepends RESET:ALL
ns.needsCharacterReset = false

function ns.SendFullMorphState()
    local settings = ns.GetSettings()

    if not settings.saveMorphState then
        if ns.needsCharacterReset then
            ns.SendRawMorphCommand("RESET:ALL")
            ns.needsCharacterReset = false
        end
        return
    end
    if not TransmorpherCharacterState then return end

    local cmdQueue = {}

    -- Sync settings to DLL first
    table.insert(cmdQueue, "SET:DBW:" .. (settings.showDBWProc and "1" or "0"))
    table.insert(cmdQueue, "SET:META:" .. (settings.showMetamorphosis and "1" or "0"))
    table.insert(cmdQueue, "SET:SHAPE:" .. (settings.morphInShapeshift and "1" or "0"))

    -- Character reset if needed
    if ns.needsCharacterReset then
        table.insert(cmdQueue, "RESET:ALL")
        ns.needsCharacterReset = false
    end

    local activeMorph = ns.currentFormMorph or TransmorpherCharacterState.Morph
    local hasActiveFormMorph = ns.currentFormMorph and ns.currentFormMorph > 0

    if hasActiveFormMorph then
        ns.morphSuspended = false
        table.insert(cmdQueue, "RESUME")
    end

    -- If suspended, still send morph data so DLL knows what to resume to
    if (ns.IsModelChangingForm() and not hasActiveFormMorph) or (ns.dbwSuspended and not hasActiveFormMorph) or ns.vehicleSuspended then
        table.insert(cmdQueue, "SUSPEND")

        if TransmorpherCharacterState.Scale then
            table.insert(cmdQueue, "SCALE:" .. TransmorpherCharacterState.Scale)
        end
        if activeMorph then
            table.insert(cmdQueue, "MORPH:" .. activeMorph)
        end
        if TransmorpherCharacterState.MountDisplay and settings.saveMountMorph then
            table.insert(cmdQueue, "MOUNT_MORPH:" .. TransmorpherCharacterState.MountDisplay)
        end
        if TransmorpherCharacterState.Items then
            for slot, item in pairs(TransmorpherCharacterState.Items) do
                table.insert(cmdQueue, "ITEM:" .. slot .. ":" .. item)
            end
        end
        if TransmorpherCharacterState.SpellMorphs then
            for sourceSpellId, targetSpellId in pairs(TransmorpherCharacterState.SpellMorphs) do
                if sourceSpellId and targetSpellId and sourceSpellId > 0 and targetSpellId > 0 then
                    table.insert(cmdQueue, "SPELL_MORPH:" .. sourceSpellId .. ":" .. targetSpellId)
                end
            end
        end

        if #cmdQueue > 0 then
            ns.SendRawMorphCommand(table.concat(cmdQueue, "|"))
        end
        return
    end

    -- Force RESUME if settings allow morph in shapeshift
    if settings.morphInShapeshift and (GetShapeshiftForm() > 0) then
        ns.morphSuspended = false
        table.insert(cmdQueue, "RESUME")
    end
    if not settings.showDBWProc and ns.HasDBWProc() then
        ns.dbwSuspended = false
        table.insert(cmdQueue, "RESUME")
    end

    -- Build morph data
    if TransmorpherCharacterState.Scale then
        table.insert(cmdQueue, "SCALE:" .. TransmorpherCharacterState.Scale)
    end
    if activeMorph then
        table.insert(cmdQueue, "MORPH:" .. activeMorph)
    end

    -- Handle Mount Morph (single per-character mount morph)
    if settings.saveMountMorph then
        local mountMorph = TransmorpherCharacterState.MountDisplay
        if not TransmorpherCharacterState.MountHidden then
            if TransmorpherCharacterState.MountDisplay == -1 then
                TransmorpherCharacterState.MountDisplay = nil
            end
            if mountMorph == -1 then
                mountMorph = nil
            end
        end
        
        -- Override with -1 ONLY if explicitly hidden by the eye button
        if TransmorpherCharacterState.MountHidden then
            mountMorph = -1
        end
        
        if IsMounted() then
            table.insert(cmdQueue, "SET:MOUNTED:1")
        end

        if mountMorph then
            table.insert(cmdQueue, "MOUNT_MORPH:" .. mountMorph)
        end
    end

    if TransmorpherCharacterState.PetDisplay and settings.savePetMorph then
        table.insert(cmdQueue, "PET_MORPH:" .. TransmorpherCharacterState.PetDisplay)
    end
    if TransmorpherCharacterState.HunterPetDisplay and (settings.saveCombatPetMorph or settings.saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_MORPH:" .. TransmorpherCharacterState.HunterPetDisplay)
    end
    if TransmorpherCharacterState.HunterPetScale and (settings.saveCombatPetMorph or settings.saveHunterPetMorph) then
        table.insert(cmdQueue, "HPET_SCALE:" .. TransmorpherCharacterState.HunterPetScale)
    end
    if TransmorpherCharacterState.EnchantMH then
        table.insert(cmdQueue, "ENCHANT_MH:" .. TransmorpherCharacterState.EnchantMH)
    end
    if TransmorpherCharacterState.EnchantOH then
        table.insert(cmdQueue, "ENCHANT_OH:" .. TransmorpherCharacterState.EnchantOH)
    end
    if TransmorpherCharacterState.TitleID then
        table.insert(cmdQueue, "TITLE:" .. TransmorpherCharacterState.TitleID)
    end
    if TransmorpherCharacterState.Items then
        for slot, item in pairs(TransmorpherCharacterState.Items) do
            local sendId = item
            if TransmorpherCharacterState.HiddenItems and TransmorpherCharacterState.HiddenItems[slot] then
                sendId = -1
            end
            table.insert(cmdQueue, "ITEM:" .. slot .. ":" .. sendId)
        end
    end
    -- Also handle hidden slots that are NOT morphed
    if TransmorpherCharacterState.HiddenItems then
        for slot, isHidden in pairs(TransmorpherCharacterState.HiddenItems) do
            if isHidden and not TransmorpherCharacterState.Items[slot] then
                table.insert(cmdQueue, "ITEM:" .. slot .. ":-1")
            end
        end
    end
    if TransmorpherCharacterState.SpellMorphs then
        for sourceSpellId, targetSpellId in pairs(TransmorpherCharacterState.SpellMorphs) do
            if sourceSpellId and targetSpellId and sourceSpellId > 0 and targetSpellId > 0 then
                table.insert(cmdQueue, "SPELL_MORPH:" .. sourceSpellId .. ":" .. targetSpellId)
            end
        end
    end

    if #cmdQueue > 0 then
        ns.SendRawMorphCommand(table.concat(cmdQueue, "|"))
    end
end
