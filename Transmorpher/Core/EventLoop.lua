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
mainFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
mainFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
mainFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
mainFrame:RegisterEvent("PLAYER_LOGOUT")
mainFrame:RegisterEvent("BARBER_SHOP_OPEN")
mainFrame:RegisterEvent("BARBER_SHOP_CLOSE")
mainFrame:RegisterEvent("UNIT_SPELLCAST_START")
mainFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
mainFrame:RegisterEvent("SPELLS_CHANGED")

-- State tracking
local lastKnownForm = -1
local lastMainHand, lastOffHand = nil, nil
local lastDBWActive = false
local lastKnownMounted = false

-- ============================================================
-- TIMING & BURST CONSTANTS
-- ============================================================
local MOUNT_BURST_SHOTS_MOUNTING  = 8     -- burst commands when first mounting
local MOUNT_BURST_SHOTS_REMOUNT   = 4     -- burst commands when re-applying (already mounted)
local MOUNT_BURST_INTERVAL        = 0.05  -- seconds between mount burst commands
local FORM_BURST_SHOTS            = 3     -- burst commands when a form morph is applied
local FORM_BURST_INTERVAL         = 0.04  -- seconds between form burst commands
local FORM_RECHECK_DURATION       = 0.7   -- seconds to run form recheck polling
local FORM_RECHECK_INTERVAL       = 0.06  -- seconds between form recheck polls
local FORM_REENFORCE_COOLDOWN     = 0.35  -- seconds before periodic form morph re-enforcement
local VEHICLE_GUARD_INTERVAL      = 0.1   -- seconds between vehicle safety guard polls

-- ============================================================
-- Smart Interaction Intervention — pre-emptive vehicle detection
-- ============================================================
local function HandleSmartIntervention(unit)
    if not unit or not UnitExists(unit) then return end
    local name = UnitName(unit) or ""
    local isVehicle = false

    -- Automated seat detection
    local seatCount = UnitVehicleSeatCount(unit)
    if seatCount and seatCount > 0 then isVehicle = true end

    -- Keyword detection
    if not isVehicle then
        for _, p in ipairs(ns.vehicleKeywords) do
            if name:find(p) then isVehicle = true; break end
        end
    end

    -- EXCLUDE: Local player (prevents intervention when mounting multi-seat mounts)
    if UnitIsUnit(unit, "player") then return end

    if isVehicle and not ns.vehicleSuspended then
        ns.vehicleSuspended = true
        ns.wasInVehicleLastFrame = true
        ns.savedMountDisplayForVehicle = (TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay) or true
        ns.SendRawMorphCommand("MOUNT_RESET|SUSPEND")
    end
end

-- Hook right-click on WorldFrame
WorldFrame:HookScript("OnMouseDown", function(_, button)
    if button == "RightButton" then HandleSmartIntervention("mouseover") end
end)
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

local function ScheduleMorphSend(delay)
    delayedSendTimer.remaining = delay or 0.05; delayedSendTimer:Show()
end

-- ============================================================
-- MOUNT LOGIC (Simplified & Consolidated)
-- ============================================================

function ns.GetActiveMountSpellID()
    if not IsMounted() then return nil end
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        if ns.mountSpellLookup and ns.mountSpellLookup[spellID] then
            return spellID
        end
    end
    return nil
end

function ns.GetTargetMountDisplayID(forcedSpellID)
    if not TransmorpherCharacterState then return nil end
    local state = TransmorpherCharacterState
    if state.MountHidden then return -1 end
    local activeSpellID = forcedSpellID or ns.GetActiveMountSpellID()
    if activeSpellID and state.Mounts and state.Mounts[activeSpellID] then
        return state.Mounts[activeSpellID]
    end
    return state.MountDisplay
end

local mountBurstShots = 0
local mountBurstID = 0
local mountBurstFrame = CreateFrame("Frame")
mountBurstFrame:Hide()
mountBurstFrame.elapsed = 0
mountBurstFrame:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed < MOUNT_BURST_INTERVAL then return end
    self.elapsed = 0
    if ns.vehicleSuspended then self:Hide(); return end
    if mountBurstShots > 0 then
        ns.SendRawMorphCommand("MOUNT_MORPH:" .. mountBurstID)
        mountBurstShots = mountBurstShots - 1
    else self:Hide() end
end)

function ns.ApplyMountMorph(isMounting, forcedSpellID)
    if not ns.IsMorpherReady() or ns.vehicleSuspended then return end
    local targetID = ns.GetTargetMountDisplayID(forcedSpellID) or 0
    if targetID == 0 then
        ns.SendRawMorphCommand("MOUNT_RESET")
        return
    end
    mountBurstID = targetID
    if isMounting then
        ns.SendRawMorphCommand("SET:MOUNTED:1")
        mountBurstShots = MOUNT_BURST_SHOTS_MOUNTING
        mountBurstFrame:Show()
    else
        -- When re-applying (already mounted), use a shorter burst to ensure it survives model changes
        mountBurstShots = MOUNT_BURST_SHOTS_REMOUNT
        mountBurstFrame:Show()
    end
end

-- Ensure MountManager namespace exists for compatibility
ns.MountManager = {
    GetActiveMountSpellID = ns.GetActiveMountSpellID,
    ApplyCorrectMorph = ns.ApplyMountMorph,
    GetTargetDisplayID = ns.GetTargetMountDisplayID
}

-- ============================================================
-- FORM & BUFF CHECK
-- ============================================================
ns.currentFormMorph = nil
ns.formMorphRuntimeActive = false
local lastFormMorphApplyAt = 0

local formRecheckFrame = CreateFrame("Frame")
formRecheckFrame:Hide()
formRecheckFrame.remaining = 0
formRecheckFrame.interval = 0.06
formRecheckFrame.elapsed = 0
formRecheckFrame:SetScript("OnUpdate", function(self, dt)
    self.remaining = self.remaining - dt
    self.elapsed = self.elapsed + dt
    if self.elapsed >= self.interval then
        self.elapsed = 0
        ns.CheckFormMorphs()
    end
    if self.remaining <= 0 then
        self:Hide()
    end
end)

local function ScheduleFormRecheck(duration, interval)
    formRecheckFrame.remaining = duration or 0.7
    formRecheckFrame.interval = interval or 0.06
    formRecheckFrame.elapsed = 0
    formRecheckFrame:Show()
end

local formBurstFrame = CreateFrame("Frame")
formBurstFrame:Hide()
formBurstFrame.displayID = nil
formBurstFrame.elapsed = 0
formBurstFrame.interval = FORM_BURST_INTERVAL
formBurstFrame.shotsLeft = 0
formBurstFrame:SetScript("OnUpdate", function(self, dt)
    if not self.displayID or self.shotsLeft <= 0 then
        self:Hide()
        return
    end
    self.elapsed = self.elapsed + dt
    if self.elapsed < self.interval then return end
    self.elapsed = 0
    -- Cancel burst if vehicle entered
    if ns.vehicleSuspended then
        self:Hide(); self.displayID = nil; self.shotsLeft = 0
        return
    end
    -- Cancel burst if the active form morph changed (form switched or buff expired)
    if ns.currentFormMorph ~= self.displayID then
        self:Hide(); self.displayID = nil; self.shotsLeft = 0
        return
    end
    local needResume = false
    if ns.dbwSuspended then
        needResume = true; ns.dbwSuspended = false
    end
    if ns.morphSuspended and not ns.vehicleSuspended then
        needResume = true; ns.morphSuspended = false
    end
    if needResume then
        ns.SendRawMorphCommand("RESUME|MORPH:" .. self.displayID)
    else
        ns.SendRawMorphCommand("MORPH:" .. self.displayID)
    end

    -- Re-apply mount morph if currently mounted to prevent it from resetting
    if IsMounted() then
        ns.ApplyMountMorph(false)
    end
    self.shotsLeft = self.shotsLeft - 1
    lastFormMorphApplyAt = GetTime()
    if self.shotsLeft <= 0 then
        self:Hide()
    end
end)

local function StartFormBurst(displayID)
    if not displayID then return end
    formBurstFrame.displayID = displayID
    formBurstFrame.elapsed = 0
    formBurstFrame.interval = FORM_BURST_INTERVAL
    formBurstFrame.shotsLeft = FORM_BURST_SHOTS
    formBurstFrame:Show()
end

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
    -- Priority 1: Active shapeshift form (Druid/Shaman/Warlock forms)
    local idx = GetShapeshiftForm()
    if idx and idx > 0 then
        -- Try 5th return (some servers/versions provide spellID directly)
        local _, _, _, _, spellID = GetShapeshiftFormInfo(idx)
        -- Fallback: match form name to known spell IDs (3.3.5a only returns 4 values)
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

    -- Priority 2: Buff-based forms (DBW, etc.) — return FIRST match, not last
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        local morph = ResolveAssignedMorphForSpell(spellID)
        if morph then return morph end
    end

    return nil
end

local function ApplyTemporaryFormMorph(displayID)
    if not displayID then return end
    local needResume = false
    if ns.dbwSuspended then
        needResume = true; ns.dbwSuspended = false
    end
    if ns.morphSuspended and not ns.vehicleSuspended then
        needResume = true; ns.morphSuspended = false
    end
    if needResume then
        ns.SendRawMorphCommand("RESUME|MORPH:" .. displayID)
    else
        ns.SendRawMorphCommand("MORPH:" .. displayID)
    end

    -- Re-apply mount morph if currently mounted to prevent it from resetting
    if IsMounted() then
        ns.ApplyMountMorph(false)
    end
    lastFormMorphApplyAt = GetTime()
end

local function RestoreBaseMorphAfterForm()
    local baseMorph = TransmorpherCharacterState and TransmorpherCharacterState.Morph
    local baseCmd = (baseMorph and baseMorph > 0) and ("MORPH:" .. baseMorph) or "MORPH:0"
    
    local shouldSuspend = ns.IsModelChangingForm()
    
    if shouldSuspend then
        -- We are in another native form (e.g. from Cat to Bear or travel)
        -- If no morph is assigned to the new form, we should suspend to show native
        if not ns.dbwSuspended and not ns.vehicleSuspended then
            ns.morphSuspended = true
            ns.SendRawMorphCommand(baseCmd .. "|SUSPEND")
        end
    else
        -- We are back to humanoid
        ns.morphSuspended = false
        if not ns.dbwSuspended and not ns.vehicleSuspended then
            -- Force a RESUME before sending the base morph to ensure it applies
            ns.SendRawMorphCommand("RESUME|" .. baseCmd)
        else
            ns.SendRawMorphCommand(baseCmd)
        end
        
        -- Re-apply items/enchants that may have been lost during form
        if TransmorpherCharacterState and TransmorpherCharacterState.EnchantMH then
            ns.SendRawMorphCommand("ENCHANT_MH:" .. TransmorpherCharacterState.EnchantMH)
        end
        if TransmorpherCharacterState and TransmorpherCharacterState.EnchantOH then
            ns.SendRawMorphCommand("ENCHANT_OH:" .. TransmorpherCharacterState.EnchantOH)
        end

        -- Re-apply mount morph if currently mounted
        if IsMounted() then
            ns.ApplyMountMorph(false)
        end
    end
end

function ns.CheckFormMorphs()
    -- Vehicle takes absolute priority — kill all form morphing
    if ns.vehicleSuspended then
        if formBurstFrame:IsShown() then
            formBurstFrame:Hide(); formBurstFrame.displayID = nil; formBurstFrame.shotsLeft = 0
        end
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
        -- If morph changed, cancel any running burst for the OLD morph first
        if morphChanged then
            if formBurstFrame:IsShown() then
                formBurstFrame:Hide(); formBurstFrame.displayID = nil; formBurstFrame.shotsLeft = 0
            end
            ApplyTemporaryFormMorph(newMorph)
            StartFormBurst(newMorph)
        elseif not ns.formMorphRuntimeActive then
            ApplyTemporaryFormMorph(newMorph)
            StartFormBurst(newMorph)
        elseif (GetTime() - lastFormMorphApplyAt) > FORM_REENFORCE_COOLDOWN then
            -- Periodic re-enforcement to prevent leaking
            ns.SendRawMorphCommand("MORPH:" .. newMorph)
            lastFormMorphApplyAt = GetTime()
        end
        ns.currentFormMorph = newMorph
        ns.formMorphRuntimeActive = true
        if ns.BroadcastMorphState and morphChanged then ns.BroadcastMorphState(true) end
        return
    end

    -- No form morph needed — clean up
    if formBurstFrame:IsShown() then
        formBurstFrame:Hide(); formBurstFrame.displayID = nil; formBurstFrame.shotsLeft = 0
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
        if not ns.dbwSuspended and not ns.vehicleSuspended then ns.SendRawMorphCommand("RESUME") end
    end

    if ns.BroadcastMorphState and (morphChanged or wasFormActive) then ns.BroadcastMorphState(true) end
end

-- ============================================================
-- Main Event Handler
-- ============================================================
mainFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGOUT" then
        ns.SendRawMorphCommand("RESET:SILENT")
        return
    end

    if event == "PLAYER_LOGIN" then
        -- Initialize DLL settings immediately
        if ns.InitializeDLLSettings then
            ns.InitializeDLLSettings()
        end
        ns.p2pEnabled = ns.GetSettings().enableWorldSync ~= false
        
        -- Clear sync state for character switch
        if ns.P2PResetForNewCharacter then
            ns.P2PResetForNewCharacter()
        end
        
        if not TransmorpherCharacterState then
            TransmorpherCharacterState = {Items={}, Morph=nil, Scale=nil, MountDisplay=nil, PetDisplay=nil, Mounts={}, HunterPetDisplay=nil, HunterPetScale=nil, EnchantMH=nil, EnchantOH=nil, TitleID=nil, Forms={}, WeaponSets={}}
        end
        if not TransmorpherCharacterState.Items then TransmorpherCharacterState.Items = {} end
        if not TransmorpherCharacterState.Forms then TransmorpherCharacterState.Forms = {} end
        if not TransmorpherCharacterState.Mounts then TransmorpherCharacterState.Mounts = {} end
        -- Only reset MountHidden if it wasn't explicitly saved
        if TransmorpherCharacterState.MountHidden == nil then
            TransmorpherCharacterState.MountHidden = false
        end
        if not TransmorpherCharacterState.WeaponSets then TransmorpherCharacterState.WeaponSets = {} end
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
        ns.needsCharacterReset = true
        lastKnownForm = GetShapeshiftForm()
        lastKnownMounted = IsMounted() or false

        ns.CheckFormMorphs() -- Initial check
        ScheduleFormRecheck(0.9, 0.06)

        -- Fallback if no form morph active
        if not ns.currentFormMorph then
            ns.morphSuspended = ns.IsModelChangingForm()
            ns.dbwSuspended = ns.GetSettings().showDBWProc and ns.HasDBWProc() or false
            lastDBWActive = ns.dbwSuspended
            ns.vehicleSuspended = UnitInVehicle("player")

            if ns.vehicleSuspended and TransmorpherCharacterState then
                ns.savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay or true
                ns.SendRawMorphCommand("MOUNT_RESET")
            end

            if ns.morphSuspended or ns.dbwSuspended or ns.vehicleSuspended then
                ns.SendRawMorphCommand("SUSPEND")
            end
        end

        if IsMounted() then
             ns.SendRawMorphCommand("SET:MOUNTED:1")
             ns.ApplyMountMorph(true)
        end
        ScheduleMorphSend(0.4)
        ns.RestoreMorphedUI()

        -- Multiplayer Sync
        if ns.BroadcastMorphState then ns.BroadcastMorphState(true) end
        
        -- Join Sync Channel ONLY if world sync is enabled
        if ns.p2pEnabled and JoinChannelByName then
            JoinChannelByName("TransmorpherSync")
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        lastKnownForm = GetShapeshiftForm()
        lastKnownMounted = IsMounted() or false
        
        ns.CheckFormMorphs()
        ScheduleFormRecheck(0.8, 0.06)

        if not ns.currentFormMorph then
            ns.morphSuspended = ns.IsModelChangingForm()
            ns.dbwSuspended = ns.GetSettings().showDBWProc and ns.HasDBWProc() or false
            lastDBWActive = ns.dbwSuspended
            ns.vehicleSuspended = UnitInVehicle("player")

            if ns.vehicleSuspended then
                ns.savedMountDisplayForVehicle = (TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay) or true
                ns.SendRawMorphCommand("MOUNT_RESET")
            end

            if ns.morphSuspended or ns.dbwSuspended or ns.vehicleSuspended then
                ns.SendRawMorphCommand("SUSPEND")
            else
                ScheduleMorphSend(0.05)
            end
        end

        if IsMounted() then
             ns.SendRawMorphCommand("SET:MOUNTED:1")
             ns.ApplyMountMorph(true)
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
        ScheduleFormRecheck(0.7, 0.05)
        
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            local settings = ns.GetSettings()
            local dbwActiveNow = settings.showDBWProc and ns.HasDBWProc()
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
            ns.CheckFormMorphs()
            ScheduleFormRecheck(0.6, 0.05)
        end
        if IsMounted() then
            ns.ApplyMountMorph(false)
        end

    elseif event == "UNIT_MODEL_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end
        local curMounted = IsMounted() or false
        if curMounted ~= lastKnownMounted then
            lastKnownMounted = curMounted
            if curMounted then
                ns.SendRawMorphCommand("SET:MOUNTED:1")
                ns.ApplyMountMorph(true)
            else
                ns.SendRawMorphCommand("MOUNT_RESET|SET:MOUNTED:0")
            end
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
                    ns.ApplyMountMorph(true, spellID)
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
            if TransmorpherCharacterState then
                if TransmorpherCharacterState.EnchantMH and curMH then
                    ns.SendMorphCommand("ENCHANT_MH:"..TransmorpherCharacterState.EnchantMH)
                    if mainFrame.enchantSlots and mainFrame.enchantSlots["Enchant MH"] then
                        local eid = TransmorpherCharacterState.EnchantMH
                        local eName = ns.enchantDB and ns.enchantDB[eid] or tostring(eid)
                        mainFrame.enchantSlots["Enchant MH"]:SetEnchant(eid, eName)
                        mainFrame.enchantSlots["Enchant MH"].isMorphed = true
                        ns.ShowMorphGlow(mainFrame.enchantSlots["Enchant MH"], "orange")
                    end
                end
                if TransmorpherCharacterState.EnchantOH and curOH then
                    ns.SendMorphCommand("ENCHANT_OH:"..TransmorpherCharacterState.EnchantOH)
                    if mainFrame.enchantSlots and mainFrame.enchantSlots["Enchant OH"] then
                        local eid = TransmorpherCharacterState.EnchantOH
                        local eName = ns.enchantDB and ns.enchantDB[eid] or tostring(eid)
                        mainFrame.enchantSlots["Enchant OH"]:SetEnchant(eid, eName)
                        mainFrame.enchantSlots["Enchant OH"].isMorphed = true
                        ns.ShowMorphGlow(mainFrame.enchantSlots["Enchant OH"], "orange")
                    end
                end
            end
            if ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05)
            elseif ns.SyncDressingRoom then ns.SyncDressingRoom() end
        end

    elseif event == "UNIT_ENTERED_VEHICLE" then
        local unit = ...
        if unit ~= "player" then return end
        if not ns.vehicleSuspended then
            ns.vehicleSuspended = true
            ns.savedMountDisplayForVehicle = (TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay) or true
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
        ScheduleFormRecheck(0.7, 0.06)

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
    guard.elapsed = 0
    guard:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < VEHICLE_GUARD_INTERVAL then return end
        self.elapsed = 0
        if not TRANSMORPHER_DLL_LOADED then return end
        local inVehicle = UnitInVehicle("player")
        if not inVehicle and UnitExists("target") then
            local sc = UnitVehicleSeatCount("target")
            if sc and sc > 0 then inVehicle = true
            else
                local name = UnitName("target") or ""
                for _, p in ipairs(ns.vehicleKeywords) do if name:find(p) then inVehicle = true; break end end
            end
        end
        if inVehicle and not ns.wasInVehicleLastFrame then
            ns.wasInVehicleLastFrame = true
            if not ns.vehicleSuspended then
                ns.vehicleSuspended = true
                ns.savedMountDisplayForVehicle = (TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay) or true
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
