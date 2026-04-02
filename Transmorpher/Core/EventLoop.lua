local addon, ns = ...

-- ============================================================
-- EVENT LOOP — Game events, vehicle detection, shapeshift,
-- enchant persistence, mount/zone transitions
-- ============================================================

local mainFrame = ns.mainFrame

-- Register all needed events
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
mainFrame:RegisterEvent("UNIT_MODEL_CHANGED")
mainFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
mainFrame:RegisterEvent("UNIT_AURA")
mainFrame:RegisterEvent("CHAT_MSG_ADDON")
mainFrame:RegisterEvent("CHAT_MSG_CHANNEL")
mainFrame:RegisterEvent("CHAT_MSG_WHISPER")
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("PLAYER_DEAD")
mainFrame:RegisterEvent("PLAYER_ALIVE")
mainFrame:RegisterEvent("PLAYER_UNGHOST")
mainFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
mainFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
mainFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
mainFrame:RegisterEvent("PLAYER_LOGOUT")
mainFrame:RegisterEvent("BARBER_SHOP_OPEN")
mainFrame:RegisterEvent("BARBER_SHOP_CLOSE")
mainFrame:RegisterEvent("UNIT_SPELLCAST_START")
mainFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
mainFrame:RegisterEvent("SPELLS_CHANGED")
mainFrame:RegisterEvent("UNIT_PET")
mainFrame:RegisterEvent("PET_BAR_UPDATE")

-- State tracking
local lastKnownForm = -1
local lastMainHand, lastOffHand = nil, nil
local lastDBWActive = false
local lastKnownMounted = false
local lastMetaAuraActive = false
local ScheduleMorphSend

local function CacheVehicleMountState()
    if not TransmorpherCharacterState then
        ns.savedMountDisplayForVehicle = false
        return
    end

    local hasMountVisual = false
    if TransmorpherCharacterState.MountHidden then
        hasMountVisual = true
    elseif TransmorpherCharacterState.MountDisplay and TransmorpherCharacterState.MountDisplay > 0 then
        hasMountVisual = true
    elseif TransmorpherCharacterState.Mounts then
        for _, displayID in pairs(TransmorpherCharacterState.Mounts) do
            if displayID and displayID > 0 then
                hasMountVisual = true
                break
            end
        end
    end

    ns.savedMountDisplayForVehicle = hasMountVisual
end

local function HasMetamorphosisAura()
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        if spellID == 47241 then
            return true
        end
    end
    return false
end

local function ForceMetaRecovery()
    if ns.vehicleSuspended or ns.dbwSuspended then return end
    ns.morphSuspended = false
    if ns.SendRawMorphCommand then
        ns.SendRawMorphCommand("RESUME")
    end
    ScheduleMorphSend(0.02)
    ScheduleMorphSend(0.12)
end

-- ============================================================
-- Smart Interaction Intervention — pre-emptive vehicle detection
-- ============================================================
local function HandleSmartIntervention(unit)
    if not unit or not UnitExists(unit) then return end
    if UnitIsUnit(unit, "player") then return end

    local seatCount = UnitVehicleSeatCount(unit)
    if not (seatCount and seatCount > 0) then return end

    if not ns.vehicleSuspended then
        ns.vehicleSuspended = true
        ns.wasInVehicleLastFrame = true
        CacheVehicleMountState()
        ns.SendRawMorphCommand("MOUNT_RESET|SUSPEND")
    end
end

if InteractUnit then hooksecurefunc("InteractUnit", HandleSmartIntervention) end

-- ============================================================
-- Delayed Send Timer
-- ============================================================
local delayedSendTimer = CreateFrame("Frame")
delayedSendTimer:Hide(); delayedSendTimer.remaining = 0
delayedSendTimer:SetScript("OnUpdate", function(self, elapsed)
    self.remaining = self.remaining - elapsed
    if self.remaining <= 0 then self:Hide(); ns.SendFullMorphState() end
end)

function ScheduleMorphSend(delay)
    -- Debounce: always reset the timer to prevent duplicate sends
    delayedSendTimer.remaining = delay or 0.05
    delayedSendTimer:Show()
end

-- ============================================================
-- PET MORPH RE-APPLICATION
-- ============================================================
local petApplyTimer = CreateFrame("Frame")
petApplyTimer:Hide()
petApplyTimer.remaining = 0
petApplyTimer:SetScript("OnUpdate", function(self, elapsed)
    self.remaining = self.remaining - elapsed
    if self.remaining <= 0 then
        self:Hide()
        if ns.ApplyPetMorphs then ns.ApplyPetMorphs() end
    end
end)

local function SchedulePetMorphApply(delay)
    petApplyTimer.remaining = delay or 0.1
    petApplyTimer:Show()
end

-- ============================================================
-- MOUNT LOGIC (Simplified & Consolidated)
-- ============================================================

-- Mount logic is handled by ns.MountManager in MountManager.lua

-- ============================================================
-- FORM & BUFF CHECK
-- ============================================================
ns.currentFormMorph = nil
ns.formMorphRuntimeActive = false

local function ResolveAssignedMorphForSpell(spellID)
    if not spellID then return nil end
    local group = ns.spellToFormGroup and ns.spellToFormGroup[spellID]
    if group then
        local groupMorph = ns.GetFormMorph(group)
        if groupMorph then return groupMorph end
    end
    return ns.GetFormMorph(spellID)
end

local function ResolveActiveFormMorph()
    -- Priority 1: Active shapeshift form
    local idx = GetShapeshiftForm()
    if idx and idx > 0 then
        local _, _, _, _, spellID = GetShapeshiftFormInfo(idx)
        if not spellID then
            local _, formName = GetShapeshiftFormInfo(idx)
            if formName then
                for sid, _ in pairs(ns.spellToFormGroup) do
                    local sName = GetSpellInfo(sid)
                    if sName and sName == formName then
                        spellID = sid
                        break
                    end
                end
            end
        end
        if spellID then
            local morph = ResolveAssignedMorphForSpell(spellID)
            if morph then return morph end
        end
    end

    -- Priority 2: Buff-based forms
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        local morph = ResolveAssignedMorphForSpell(spellID)
        if morph then return morph end
    end

    return nil
end

local function RestoreBaseMorphAfterForm()
    local baseMorph = TransmorpherCharacterState and TransmorpherCharacterState.Morph
    local baseCmd = (baseMorph and baseMorph > 0) and ("MORPH:" .. baseMorph) or "MORPH:0"
    
    if ns.IsModelChangingForm() then
        if not ns.dbwSuspended and not ns.vehicleSuspended then
            ns.morphSuspended = true
            ns.SendRawMorphCommand(baseCmd .. "|SUSPEND")
        end
    else
        ns.morphSuspended = false
        if not ns.dbwSuspended and not ns.vehicleSuspended then
            ns.SendRawMorphCommand("RESUME|" .. baseCmd)
            ScheduleMorphSend(0.05)
        else
            ns.SendRawMorphCommand(baseCmd)
        end
        
        -- Re-apply items/enchants
        if TransmorpherCharacterState then
            if TransmorpherCharacterState.EnchantMH then ns.SendRawMorphCommand("ENCHANT_MH:" .. TransmorpherCharacterState.EnchantMH) end
            if TransmorpherCharacterState.EnchantOH then ns.SendRawMorphCommand("ENCHANT_OH:" .. TransmorpherCharacterState.EnchantOH) end
        end

        if IsMounted() then ns.MountManager.ApplyCorrectMorph(false) end
    end
end

function ns.CheckFormMorphs()
    if ns.vehicleSuspended then
        if ns.formMorphRuntimeActive then
            ns.formMorphRuntimeActive = false
            ns.currentFormMorph = nil
            if ns.BroadcastMorphState then ns.BroadcastMorphState(true) end
        end
        return
    end

    local wasFormActive = ns.formMorphRuntimeActive
    local newMorph = ResolveActiveFormMorph()
    local morphChanged = (newMorph ~= ns.currentFormMorph)

    if newMorph then
        ns.currentFormMorph = newMorph
        ns.formMorphRuntimeActive = true
        
        local cmd = "MORPH:" .. newMorph
        if ns.dbwSuspended or ns.morphSuspended then
            ns.dbwSuspended = false
            ns.morphSuspended = false
            ns.SendRawMorphCommand("RESUME|" .. cmd)
        else
            ns.SendRawMorphCommand(cmd)
        end
        
        if IsMounted() then ns.MountManager.ApplyCorrectMorph(false) end
        if ns.BroadcastMorphState and morphChanged then ns.BroadcastMorphState(true) end
        return
    end

    if ns.formMorphRuntimeActive then
        RestoreBaseMorphAfterForm()
    end
    ns.formMorphRuntimeActive = false
    ns.currentFormMorph = nil

    local shouldSuspend = ns.IsModelChangingForm()
    if shouldSuspend and not ns.morphSuspended then
        ns.morphSuspended = true
        if not ns.dbwSuspended and not ns.vehicleSuspended then ns.SendRawMorphCommand("SUSPEND") end
    elseif not shouldSuspend and ns.morphSuspended then
        ns.morphSuspended = false
        if not ns.dbwSuspended and not ns.vehicleSuspended then
            local baseMorph = TransmorpherCharacterState and TransmorpherCharacterState.Morph
            local resumeCmd = (baseMorph and baseMorph > 0) and ("RESUME|MORPH:" .. baseMorph) or "RESUME"
            ns.SendRawMorphCommand(resumeCmd)
            ScheduleMorphSend(0.05)
        end
    end

    if ns.BroadcastMorphState and (morphChanged or wasFormActive) then ns.BroadcastMorphState(true) end
end

-- ============================================================
-- Main Event Handler
-- ============================================================
mainFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGOUT" then
        TRANSMORPHER_CMD = ""
        TRANSMORPHER_LOG = ""
        ns.SendRawMorphCommand("RESET:SILENT")
        return
    end

    if event == "SPELLS_CHANGED" then
        if ns.SyncPlayerSpellbookVisibility then
            ns.SyncPlayerSpellbookVisibility()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        TRANSMORPHER_CMD = ""
        TRANSMORPHER_LOG = ""
        -- Initialize DLL settings immediately
        if ns.InitializeDLLSettings then
            ns.InitializeDLLSettings()
        end
        if not ns.IsModelChangingForm() then
            ns.SendRawMorphCommand("RESUME") -- Force clean state on login only when form should not stay native
        end
        ns.p2pEnabled = ns.GetSettings().enableWorldSync ~= false
        
        -- Clear sync state for character switch
        if ns.P2PResetForNewCharacter then
            ns.P2PResetForNewCharacter()
        end
        
        if not TransmorpherCharacterState then
            TransmorpherCharacterState = {Items={}, Morph=nil, Scale=nil, MountDisplay=nil, PetDisplay=nil, Mounts={}, HunterPetDisplay=nil, HunterPetScale=nil, EnchantMH=nil, EnchantOH=nil, TitleID=nil, Forms={}, SpellMorphs={}, WeaponSets={}}
        end
        
        -- RECOVER FROM DLL (Fixes "mount doesnt show on first login" when WTF is wiped)
        if TRANSMORPHER_DLL_STATE then
            ns.Log("DLL state found in global memory, restoring to Lua...")
            if TRANSMORPHER_DLL_STATE.morph and TRANSMORPHER_DLL_STATE.morph > 0 then
                TransmorpherCharacterState.Morph = TransmorpherCharacterState.Morph or TRANSMORPHER_DLL_STATE.morph
            end
            if TRANSMORPHER_DLL_STATE.scale and TRANSMORPHER_DLL_STATE.scale > 0.01 then
                TransmorpherCharacterState.Scale = TransmorpherCharacterState.Scale or TRANSMORPHER_DLL_STATE.scale
            end
            if TRANSMORPHER_DLL_STATE.mount and TRANSMORPHER_DLL_STATE.mount > 0 then
                TransmorpherCharacterState.MountDisplay = TransmorpherCharacterState.MountDisplay or TRANSMORPHER_DLL_STATE.mount
            end
            if TRANSMORPHER_DLL_STATE.title and TRANSMORPHER_DLL_STATE.title > 0 then
                TransmorpherCharacterState.TitleID = TransmorpherCharacterState.TitleID or TRANSMORPHER_DLL_STATE.title
            end
            if TRANSMORPHER_DLL_STATE.items then
                for slot, item in pairs(TRANSMORPHER_DLL_STATE.items) do
                    if item > 0 then
                        TransmorpherCharacterState.Items[slot] = TransmorpherCharacterState.Items[slot] or item
                    end
                end
            end
            if TRANSMORPHER_DLL_STATE.spells then
                TransmorpherCharacterState.SpellMorphs = TransmorpherCharacterState.SpellMorphs or {}
                for sourceSpellId, targetSpellId in pairs(TRANSMORPHER_DLL_STATE.spells) do
                    local source = tonumber(sourceSpellId)
                    local target = tonumber(targetSpellId)
                    if source and source > 0 and target and target > 0 then
                        TransmorpherCharacterState.SpellMorphs[source] = target
                    end
                end
            end
            -- Clear it so we don't restore it again on every reload
            TRANSMORPHER_DLL_STATE = nil
        end
        if not TransmorpherCharacterState.Items then TransmorpherCharacterState.Items = {} end
        if not TransmorpherCharacterState.Forms then TransmorpherCharacterState.Forms = {} end
        if not TransmorpherCharacterState.SpellMorphs then TransmorpherCharacterState.SpellMorphs = {} end
        if not TransmorpherCharacterState.Mounts then TransmorpherCharacterState.Mounts = {} end
        -- Only reset MountHidden if it wasn't explicitly saved
        if TransmorpherCharacterState.MountHidden == nil then
            TransmorpherCharacterState.MountHidden = false
        end
        if not TransmorpherCharacterState.WeaponSets then TransmorpherCharacterState.WeaponSets = {} end
        -- Ensure ground/flying mount fields exist
        if TransmorpherCharacterState.GroundMountDisplay and TransmorpherCharacterState.GroundMountDisplay <= 0 then
            TransmorpherCharacterState.GroundMountDisplay = nil
        end
        if TransmorpherCharacterState.FlyingMountDisplay and TransmorpherCharacterState.FlyingMountDisplay <= 0 then
            TransmorpherCharacterState.FlyingMountDisplay = nil
        end
        if TransmorpherCharacterState.MountDisplay and TransmorpherCharacterState.MountDisplay <= 0 then
            TransmorpherCharacterState.MountDisplay = nil
        end
        for spellID, displayID in pairs(TransmorpherCharacterState.Mounts) do
            if not displayID or displayID <= 0 then
                TransmorpherCharacterState.Mounts[spellID] = nil
            end
        end

        lastMainHand = GetInventoryItemLink("player", 16)
        lastOffHand = GetInventoryItemLink("player", 17)
        
        -- DLL persists full state to disk now. NEVER force a reset on login.
        -- The DLL handles character changes internally via GUID detection.
        ns.needsCharacterReset = false
        
        -- CHARACTER ISOLATION: If the GUID changed, wipe the old character's state
        -- to prevent pollutions when broadcasting.
        local currentGUID = UnitGUID("player") or ""
        if TransmorpherCharacterState and TransmorpherCharacterState._lastGUID and TransmorpherCharacterState._lastGUID ~= currentGUID then
            ns.Log("Character change detected in Lua (%s -> %s), wiping state for isolation.", TransmorpherCharacterState._lastGUID, currentGUID)
            -- Preserve settings, wipe morph state
            TransmorpherCharacterState = {
                Items = {}, Morph = nil, Scale = nil, MountDisplay = nil,
                PetDisplay = nil, Mounts = {}, HiddenItems = {}, WeaponSets = {},
                Forms = {}, SpellMorphs = {}, _lastGUID = currentGUID
            }
        end
        TransmorpherCharacterState._lastGUID = currentGUID
        
        if ns.ClearAllRuntimeSpellMorphs then
            ns.ClearAllRuntimeSpellMorphs()
        end

        lastKnownForm = GetShapeshiftForm()
        lastKnownMounted = (IsMounted() and not UnitInVehicle("player")) or false

        if ns.InitAuraSpellSwaps then
            ns.InitAuraSpellSwaps()
        end

        ns.CheckFormMorphs() -- Initial check

        -- Fallback if no form morph active
        if not ns.currentFormMorph then
            ns.morphSuspended = ns.IsModelChangingForm()
            ns.dbwSuspended = false
            lastDBWActive = ns.dbwSuspended
            ns.vehicleSuspended = UnitInVehicle("player")

            if ns.vehicleSuspended and TransmorpherCharacterState then
                CacheVehicleMountState()
                ns.SendRawMorphCommand("MOUNT_RESET")
            end

            if ns.morphSuspended or ns.dbwSuspended or ns.vehicleSuspended then
                ns.SendRawMorphCommand("SUSPEND")
            end
        end

        if lastKnownMounted then
            ns.SendRawMorphCommand("SET:MOUNTED:1")
            ns.MountManager.ApplyCorrectMorph(true)
        else
            ns.SendRawMorphCommand("SET:MOUNTED:0")
        end
        
        -- Sync is now handled immediately by ns.InitializeDLLSettings
        -- if DLL is already loaded, or when it loads.

        ns.RestoreMorphedUI()

        -- Multiplayer Sync
        if ns.BroadcastMorphState then ns.BroadcastMorphState(true) end
        
        -- Join Sync Channel ONLY if world sync is enabled
        if ns.p2pEnabled and JoinChannelByName then
            JoinChannelByName("TransmorpherSync")
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- Don't send RESUME while a native shapeshift form should remain active.
        -- That can wrongly restore the base morph during reload/login transitions.
        if not ns.IsModelChangingForm() and (ns.morphSuspended or ns.dbwSuspended or ns.vehicleSuspended) then
            ns.SendRawMorphCommand("RESUME")
        end
        lastKnownForm = GetShapeshiftForm()
        lastKnownMounted = (IsMounted() and not UnitInVehicle("player")) or false
        
        -- Reset mount manager cache so mount morph is re-sent after teleport
        if ns.MountManager.ResetForZoneChange then
            ns.MountManager.ResetForZoneChange()
        end
        
        ns.CheckFormMorphs()

        if not ns.currentFormMorph then
            ns.morphSuspended = ns.IsModelChangingForm()
            ns.dbwSuspended = false
            lastDBWActive = ns.dbwSuspended
            ns.vehicleSuspended = UnitInVehicle("player")

            if ns.vehicleSuspended then
                CacheVehicleMountState()
                ns.SendRawMorphCommand("MOUNT_RESET")
            end

            if ns.morphSuspended or ns.dbwSuspended or ns.vehicleSuspended then
                ns.SendRawMorphCommand("SUSPEND")
            end
            -- NO ScheduleMorphSend here! PLAYER_LOGIN already handles it.
            -- The DLL has persisted state, so re-sending on zone change is unnecessary.
        end

        if lastKnownMounted then
            ns.SendRawMorphCommand("SET:MOUNTED:1")
            ns.MountManager.ApplyCorrectMorph(true)
        else
            ns.SendRawMorphCommand("SET:MOUNTED:0")
        end

        if TransmorpherCharacterState and TransmorpherCharacterState.WorldTime then
            ns.SendMorphCommand("TIME:"..TransmorpherCharacterState.WorldTime)
        elseif ns.GetSettings().worldTime then
            ns.SendMorphCommand("TIME:"..ns.GetSettings().worldTime)
        end
        if TransmorpherCharacterState and TransmorpherCharacterState.TitleID then
            ns.SendMorphCommand("TITLE:"..TransmorpherCharacterState.TitleID)
        end
        
        -- Broadcast state and announce presence with delay to ensure peers are ready
        if ns.P2PBroadcastHello then
            local delayFrame = CreateFrame("Frame")
            delayFrame.elapsed = 0
            delayFrame:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = self.elapsed + elapsed
                if self.elapsed >= 1.0 then
                    self:SetScript("OnUpdate", nil)
                    ns.P2PBroadcastHello()
                    if ns.BroadcastMorphState then 
                        ns.BroadcastMorphState(true) 
                    end
                end
            end)
        elseif ns.BroadcastMorphState then 
            ns.BroadcastMorphState(true) 
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        -- Environmental trigger handled by MountManager
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        local currentForm = GetShapeshiftForm()
        -- if currentForm == lastKnownForm then return end -- Force check for custom morphs even if index same (e.g. reload)
        lastKnownForm = currentForm
        ns.CheckFormMorphs()
        -- Sync mount state: shapeshifting often dismounts the player
        local curMounted = IsMounted() and not UnitInVehicle("player")
        if not curMounted and lastKnownMounted then
            lastKnownMounted = false
            ns.SendRawMorphCommand("SET:MOUNTED:0")
        end
        local metaAuraNow = HasMetamorphosisAura()
        if lastMetaAuraActive and not metaAuraNow then
            ForceMetaRecovery()
        end
        lastMetaAuraActive = metaAuraNow
        
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            local metaAuraNow = HasMetamorphosisAura()
            if lastMetaAuraActive and not metaAuraNow then
                ForceMetaRecovery()
            end
            lastMetaAuraActive = metaAuraNow
            local settings = ns.GetSettings()
            local dbwActiveNow = (settings and settings.showDBWProc) and ns.HasDBWProc() or false
            if dbwActiveNow ~= lastDBWActive then
                lastDBWActive = dbwActiveNow
                if dbwActiveNow then
                    ns.dbwSuspended = true
                    if not ns.vehicleSuspended then
                        ns.SendRawMorphCommand("SUSPEND")
                    end
                else
                    ns.dbwSuspended = false
                    if not ns.morphSuspended and not ns.vehicleSuspended then
                        ns.SendRawMorphCommand("RESUME")
                    end
                    if ns.SendFullMorphState then
                        ns.SendFullMorphState()
                    end
                end
            end
-- REMOVED: ScheduleMorphSend on buff changes was causing flicker/invisible when buffs refresh
            -- We only check form morphs now - no refresh triggered by buff changes
            ns.CheckFormMorphs()
            if ns.ScheduleAuraSpellSwapCheck then
                ns.ScheduleAuraSpellSwapCheck()
            end
        end
        local curMounted = IsMounted() and not UnitInVehicle("player")
        if curMounted then
            ns.MountManager.ApplyCorrectMorph(false)
        elseif lastKnownMounted then
            lastKnownMounted = false
            ns.SendRawMorphCommand("SET:MOUNTED:0")
        end

    elseif event == "UNIT_MODEL_CHANGED" then
        local unit = ...
        if unit == "player" then
            local curMounted = (IsMounted() and not UnitInVehicle("player")) or false
            if curMounted ~= lastKnownMounted then
                lastKnownMounted = curMounted
                if curMounted then
                    ns.SendRawMorphCommand("SET:MOUNTED:1")
                    ns.MountManager.ApplyCorrectMorph(true)
                else
                    ns.SendRawMorphCommand("SET:MOUNTED:0")
                end
            end
        elseif unit == "pet" then
            SchedulePetMorphApply(0.12) -- Re-apply pet morph if model changed
        end

    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SENT" then
        local unit = ...
        if unit == "player" then
            local _, _, _, _, _, _, _, _, spellID = UnitCastingInfo("player")
            if not spellID and event == "UNIT_SPELLCAST_SENT" then
                 _, _, _, spellID = ...
            end
            if spellID and ns.mountSpellLookup and ns.mountSpellLookup[spellID] then
                if not ns.vehicleSuspended then
                    ns.SendRawMorphCommand("SET:MOUNTED:1")
                    ns.MountManager.ApplyCorrectMorph(true)
                end
            end
        end

    elseif event == "UNIT_INVENTORY_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end
        local curMH = GetInventoryItemLink("player", 16)
        local curOH = GetInventoryItemLink("player", 17)
        if curMH ~= lastMainHand or curOH ~= lastOffHand then
            lastMainHand = curMH; lastOffHand = curOH
            -- We no longer need to re-send enchant commands here.
            -- The DLL's Layer 1 Hook (DescriptorWriteHook) intercepts the 
            -- descriptor writes during the swap and enforces the morph 
            -- without requiring a new command or a visual 'tick' (model rebuild).
            if ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05)
            elseif ns.SyncDressingRoom then ns.SyncDressingRoom() end
        end

    elseif event == "UNIT_ENTERED_VEHICLE" then
        local unit = ...
        if unit ~= "player" then return end
        if not ns.vehicleSuspended then
            ns.vehicleSuspended = true
            CacheVehicleMountState()
            ns.SendRawMorphCommand("MOUNT_RESET|SUSPEND")
        else
            ns.SendRawMorphCommand("SUSPEND")
        end

    elseif event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit ~= "player" then return end
        if ns.vehicleSuspended then
            ns.vehicleSuspended = false
            if ns.savedMountDisplayForVehicle then
                ns.SendRawMorphCommand("RESUME")
                ns.SendFullMorphState()
                ns.savedMountDisplayForVehicle = nil
                ns.UpdateSpecialSlots()
            else ns.SendRawMorphCommand("RESUME") end
        end
        ns.CheckFormMorphs()

    elseif event == "BARBER_SHOP_OPEN" then ns.SendRawMorphCommand("SUSPEND")
    elseif event == "BARBER_SHOP_CLOSE" then ns.SendRawMorphCommand("RESUME")
    elseif event == "CHAT_MSG_ADDON" then
        if ns.P2PHandleAddonMessage then ns.P2PHandleAddonMessage(...) end
    elseif event == "CHAT_MSG_CHANNEL" then
        if ns.P2PHandleAddonMessage then 
            local msg, sender, lang, channelName = ...
            ns.P2PHandleAddonMessage(nil, msg, channelName, sender)
        end
    elseif event == "CHAT_MSG_WHISPER" then
        if ns.P2PHandleAddonMessage then
            local msg, sender = ...
            ns.P2PHandleAddonMessage(nil, msg, "WHISPER", sender)
        end
    elseif event == "PLAYER_DEAD" then
        ns.isDead = true
        ns.SendRawMorphCommand("SUSPEND") -- Stay frozen while dead/ghost
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if ns.isDead then
            ns.isDead = false
            ns.SendRawMorphCommand("RESUME")
            ScheduleMorphSend(0.2) -- Restore appearance after revival
            SchedulePetMorphApply(0.3) -- Restore pet appearance after revival
        end
    elseif event == "UNIT_PET" or event == "PET_BAR_UPDATE" then
        SchedulePetMorphApply(0.15)
    end
end)

-- ============================================================
-- AUTO-DISMOUNT / AUTO-UNSHIFT ON ERROR
-- ============================================================
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("UI_ERROR_MESSAGE")
    f:SetScript("OnEvent", function(_, _, msg)
        -- Auto-Unshift
        if msg == ERR_MOUNT_SHAPESHIFTED or msg == ERR_NOT_WHILE_SHAPESHIFTED then
            if GetShapeshiftForm() > 0 and not InCombatLockdown() then
                CancelShapeshiftForm()
            end
        -- Auto-Dismount
        elseif msg == ERR_ATTACK_MOUNTED or msg == ERR_NOT_WHILE_MOUNTED or msg == ERR_TAXIPLAYERALREADYMOUNTED then
            if IsMounted() and not InCombatLockdown() then
                Dismount()
            end
        end
    end)
end

-- ============================================================
-- VEHICLE SAFETY GUARD — aggressive polling
-- ============================================================
do
    local guard = CreateFrame("Frame")
    guard:SetScript("OnUpdate", function()
        if not TRANSMORPHER_DLL_LOADED then return end
        local inVehicle = UnitInVehicle("player")
        if inVehicle and not ns.wasInVehicleLastFrame then
            ns.wasInVehicleLastFrame = true
            if not ns.vehicleSuspended then
                ns.vehicleSuspended = true
                CacheVehicleMountState()
                ns.SendRawMorphCommand("MOUNT_RESET|SUSPEND")
            else
                ns.SendRawMorphCommand("SUSPEND")
            end
        elseif not inVehicle and ns.wasInVehicleLastFrame then
            ns.wasInVehicleLastFrame = false
            if ns.vehicleSuspended then
                ns.vehicleSuspended = false
                if ns.savedMountDisplayForVehicle then
                    ns.SendRawMorphCommand("RESUME")
                    ns.SendFullMorphState()
                    ns.savedMountDisplayForVehicle = nil
                    ns.UpdateSpecialSlots()
                else ns.SendRawMorphCommand("RESUME") end
            end
        end
    end)
end

-- ============================================================
-- MOUNT STATE SAFETY GUARD — periodic sync (catches all edge cases)
-- ============================================================
do
    local mountGuard = CreateFrame("Frame")
    local mountGuardInterval = 0
    mountGuard:SetScript("OnUpdate", function(self, elapsed)
        if not TRANSMORPHER_DLL_LOADED then return end
        mountGuardInterval = mountGuardInterval + elapsed
        if mountGuardInterval < 0.5 then return end
        mountGuardInterval = 0

        local isMounted = IsMounted() and not UnitInVehicle("player") and not ns.vehicleSuspended
        if not isMounted and lastKnownMounted then
            lastKnownMounted = false
            ns.SendRawMorphCommand("SET:MOUNTED:0")
        elseif isMounted and not lastKnownMounted then
            lastKnownMounted = true
            ns.SendRawMorphCommand("SET:MOUNTED:1")
        end
    end)
end
