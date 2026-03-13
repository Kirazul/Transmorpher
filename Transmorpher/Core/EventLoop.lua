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
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
mainFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
mainFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
mainFrame:RegisterEvent("PLAYER_LOGOUT")
mainFrame:RegisterEvent("BARBER_SHOP_OPEN")
mainFrame:RegisterEvent("BARBER_SHOP_CLOSE")

-- State tracking
local lastKnownForm = -1
local lastKnownMounted = false
local lastMainHand, lastOffHand = nil, nil
local lastDBWActive = false

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

    if isVehicle and not ns.vehicleSuspended then
        ns.vehicleSuspended = true
        ns.wasInVehicleLastFrame = true
        if TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
            ns.savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay
            ns.SendRawMorphCommand("MOUNT_RESET|SUSPEND")
            TransmorpherCharacterState.MountDisplay = nil
        else
            ns.SendRawMorphCommand("SUSPEND")
        end
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
-- Mount Fix Timer — delayed mount morph re-apply
-- ============================================================
local function ResolveMountMorphID()
    if not TransmorpherCharacterState then return nil end
    local activeMountSpellID = ns.GetActiveMountSpellID and ns.GetActiveMountSpellID()
    local mountMorphID = nil
    if activeMountSpellID and TransmorpherCharacterState.Mounts then
        mountMorphID = TransmorpherCharacterState.Mounts[activeMountSpellID]
    end
    mountMorphID = mountMorphID or TransmorpherCharacterState.MountDisplay
    if mountMorphID and mountMorphID > 0 then
        return mountMorphID
    end
    return nil
end

local mountRecoveryBurst = CreateFrame("Frame")
mountRecoveryBurst:Hide()
mountRecoveryBurst.elapsed = 0
mountRecoveryBurst.interval = 0.18
mountRecoveryBurst.shotsLeft = 0
mountRecoveryBurst:SetScript("OnUpdate", function(self, dt)
    if self.shotsLeft <= 0 then
        self:Hide()
        return
    end
    if not IsMounted() or not TransmorpherCharacterState or not ns.GetSettings().saveMountMorph then
        self:Hide()
        return
    end
    if TransmorpherCharacterState.MountHidden then
        self:Hide()
        return
    end
    self.elapsed = self.elapsed + dt
    if self.elapsed < self.interval then return end
    self.elapsed = 0
    local mountMorphID = ResolveMountMorphID()
    if mountMorphID then
        ns.SendMorphCommand("MOUNT_MORPH:"..mountMorphID)
    else
        self:Hide()
        return
    end
    self.shotsLeft = self.shotsLeft - 1
    if self.shotsLeft <= 0 then
        self:Hide()
    end
end)

local function StartMountRecoveryBurst()
    mountRecoveryBurst.elapsed = 0
    mountRecoveryBurst.shotsLeft = 8
    mountRecoveryBurst:Show()
end

local mountFixTimer = CreateFrame("Frame")
mountFixTimer:Hide(); mountFixTimer.elapsed = 0; mountFixTimer.retries = 0
mountFixTimer:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= 1.0 then
        self.elapsed = 0
        self.retries = self.retries + 1
        
        if IsMounted() and TransmorpherCharacterState and ns.GetSettings().saveMountMorph then
            if TransmorpherCharacterState.MountHidden then
                self:Hide()
                return
            end
            local mountMorphID = ResolveMountMorphID()
            if mountMorphID and mountMorphID > 0 then
                ns.SendMorphCommand("MOUNT_MORPH:"..mountMorphID)
                self:Hide() -- Success!
            elseif not mountMorphID then
                self:Hide()
            end
        else
            self:Hide() -- No longer mounted or settings disabled
        end
    end
end)

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
formBurstFrame.interval = 0.04
formBurstFrame.shotsLeft = 0
formBurstFrame:SetScript("OnUpdate", function(self, dt)
    if not self.displayID or self.shotsLeft <= 0 then
        self:Hide()
        return
    end
    self.elapsed = self.elapsed + dt
    if self.elapsed < self.interval then return end
    self.elapsed = 0
    if ns.vehicleSuspended then
        self:Hide()
        return
    end
    if ns.morphSuspended and not ns.dbwSuspended and not ns.vehicleSuspended then
        ns.morphSuspended = false
        ns.SendRawMorphCommand("RESUME|MORPH:" .. self.displayID)
    else
        ns.SendRawMorphCommand("MORPH:" .. self.displayID)
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
    formBurstFrame.interval = 0.04
    formBurstFrame.shotsLeft = 3
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
    local resolvedMorph = nil
    local idx = GetShapeshiftForm()
    if idx and idx > 0 then
        local _, _, _, _, spellID = GetShapeshiftFormInfo(idx)
        if spellID then
            resolvedMorph = ResolveAssignedMorphForSpell(spellID)
            if resolvedMorph then
                return resolvedMorph
            end
        end
    end

    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        local mid = ResolveAssignedMorphForSpell(spellID)
        if mid then
            resolvedMorph = mid
        end
    end

    return resolvedMorph
end

local function ApplyTemporaryFormMorph(displayID)
    if not displayID then return end
    if ns.morphSuspended and not ns.dbwSuspended and not ns.vehicleSuspended then
        ns.morphSuspended = false
        ns.SendRawMorphCommand("RESUME|MORPH:" .. displayID)
    else
        ns.SendRawMorphCommand("MORPH:" .. displayID)
    end
    lastFormMorphApplyAt = GetTime()
end

local function RestoreBaseMorphAfterForm()
    local baseMorph = TransmorpherCharacterState and TransmorpherCharacterState.Morph
    local baseCmd = (baseMorph and baseMorph > 0) and ("MORPH:" .. baseMorph) or "MORPH:0"
    local shouldSuspend = ns.IsModelChangingForm()
    if shouldSuspend and not ns.dbwSuspended and not ns.vehicleSuspended then
        ns.morphSuspended = true
        ns.SendRawMorphCommand(baseCmd .. "|SUSPEND")
    else
        ns.SendRawMorphCommand(baseCmd)
    end
end

function ns.CheckFormMorphs()
    if ns.vehicleSuspended then
        if formBurstFrame:IsShown() then
            formBurstFrame:Hide()
            formBurstFrame.displayID = nil
            formBurstFrame.shotsLeft = 0
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
        if morphChanged or not ns.formMorphRuntimeActive then
            ApplyTemporaryFormMorph(newMorph)
            StartFormBurst(newMorph)
        elseif (GetTime() - lastFormMorphApplyAt) > 0.35 then
            ns.SendRawMorphCommand("MORPH:" .. newMorph)
            lastFormMorphApplyAt = GetTime()
        end
        ns.currentFormMorph = newMorph
        ns.formMorphRuntimeActive = true
        if ns.BroadcastMorphState and morphChanged then ns.BroadcastMorphState(true) end
        return
    end

    if formBurstFrame:IsShown() then
        formBurstFrame:Hide()
        formBurstFrame.displayID = nil
        formBurstFrame.shotsLeft = 0
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
        if not TransmorpherCharacterState then
            TransmorpherCharacterState = {Items={}, Morph=nil, Scale=nil, MountDisplay=nil, PetDisplay=nil, Mounts={}, HunterPetDisplay=nil, HunterPetScale=nil, EnchantMH=nil, EnchantOH=nil, TitleID=nil, Forms={}, WeaponSets={}}
        end
        if not TransmorpherCharacterState.Items then TransmorpherCharacterState.Items = {} end
        if not TransmorpherCharacterState.Forms then TransmorpherCharacterState.Forms = {} end
        if not TransmorpherCharacterState.Mounts then TransmorpherCharacterState.Mounts = {} end
        TransmorpherCharacterState.MountHidden = false
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
                local hasMountMorph = TransmorpherCharacterState.MountDisplay or (TransmorpherCharacterState.Mounts and next(TransmorpherCharacterState.Mounts))
                if hasMountMorph then
                    ns.savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay or 0
                    ns.SendRawMorphCommand("MOUNT_RESET")
                end
            end

            if ns.morphSuspended or ns.dbwSuspended or ns.vehicleSuspended then
                ns.SendRawMorphCommand("SUSPEND")
            end
        end

        ScheduleMorphSend(0.4)
        if IsMounted() and not (TransmorpherCharacterState and TransmorpherCharacterState.MountHidden) then mountFixTimer.elapsed = 0; mountFixTimer.retries = 0; mountFixTimer:Show() end
        ns.RestoreMorphedUI()
        
        -- Multiplayer Sync
        if ns.BroadcastMorphState then ns.BroadcastMorphState(true) end
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

            if ns.vehicleSuspended and TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
                ns.savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay
                ns.SendMorphCommand("MOUNT_RESET")
            end

            if ns.morphSuspended or ns.dbwSuspended or ns.vehicleSuspended then
                ns.SendRawMorphCommand("SUSPEND")
            else
                ScheduleMorphSend(0.05)
            end
        end

        if TransmorpherCharacterState and TransmorpherCharacterState.WorldTime then
            ns.SendMorphCommand("TIME:"..TransmorpherCharacterState.WorldTime)
        elseif ns.GetSettings().worldTime then
            ns.SendMorphCommand("TIME:"..ns.GetSettings().worldTime)
        end
        if TransmorpherCharacterState and TransmorpherCharacterState.TitleID then
            ns.SendMorphCommand("TITLE:"..TransmorpherCharacterState.TitleID)
        end
        if IsMounted() and not (TransmorpherCharacterState and TransmorpherCharacterState.MountHidden) then mountFixTimer.elapsed = 0; mountFixTimer.retries = 0; mountFixTimer:Show() end
        if ns.BroadcastMorphState then ns.BroadcastMorphState(true) end
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

    elseif event == "UNIT_MODEL_CHANGED" then
        local unit = ...
        if unit ~= "player" then return end
        local curMounted = IsMounted() or false
        if curMounted ~= lastKnownMounted then
            lastKnownMounted = curMounted
            if curMounted and TransmorpherCharacterState and ns.GetSettings().saveMountMorph then
                local mountMorphID = ResolveMountMorphID()
                if not TransmorpherCharacterState.MountHidden and mountMorphID and mountMorphID > 0 then
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0.1, function()
                            ns.SendMorphCommand("MOUNT_MORPH:"..mountMorphID)
                        end)
                    else
                        local mountDelayFrame = CreateFrame("Frame")
                        mountDelayFrame.elapsed = 0
                        mountDelayFrame:SetScript("OnUpdate", function(delaySelf, dt)
                            delaySelf.elapsed = delaySelf.elapsed + dt
                            if delaySelf.elapsed >= 0.1 then
                                delaySelf:SetScript("OnUpdate", nil)
                                ns.SendMorphCommand("MOUNT_MORPH:"..mountMorphID)
                            end
                        end)
                    end
                end
                if mountMorphID and mountMorphID > 0 then
                    StartMountRecoveryBurst()
                else
                    mountRecoveryBurst:Hide()
                end
                mountFixTimer.elapsed = 0
                mountFixTimer.retries = 0
                mountFixTimer:Show()
            else
                mountRecoveryBurst:Hide()
                mountFixTimer:Hide()
                mountFixTimer.elapsed = 0
                mountFixTimer.retries = 0
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
            ns.SyncDressingRoom()
        end

    elseif event == "UNIT_ENTERED_VEHICLE" then
        local unit = ...
        if unit ~= "player" then return end
        if not ns.vehicleSuspended then
            ns.vehicleSuspended = true
            if TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
                ns.savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay
                ns.SendRawMorphCommand("MOUNT_RESET|SUSPEND")
                TransmorpherCharacterState.MountDisplay = nil
            else ns.SendRawMorphCommand("SUSPEND") end
        end

    elseif event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit ~= "player" then return end
        if ns.vehicleSuspended then
            ns.vehicleSuspended = false
            if ns.savedMountDisplayForVehicle then
                TransmorpherCharacterState.MountDisplay = ns.savedMountDisplayForVehicle
                ns.SendMorphCommand("MOUNT_MORPH:"..ns.savedMountDisplayForVehicle.."|RESUME")
                ns.savedMountDisplayForVehicle = nil; ns.UpdateSpecialSlots()
            else ns.SendRawMorphCommand("RESUME") end
        end
        ScheduleFormRecheck(0.7, 0.06)

    elseif event == "BARBER_SHOP_OPEN" then ns.SendRawMorphCommand("SUSPEND")
    elseif event == "BARBER_SHOP_CLOSE" then ns.SendRawMorphCommand("RESUME")
    elseif event == "CHAT_MSG_ADDON" then
        if ns.OnSyncReceived then ns.OnSyncReceived(...) end
    end
end)

-- ============================================================
-- AUTO-UNSHIFT ON MOUNT ERROR
-- ============================================================
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("UI_ERROR_MESSAGE")
    f:SetScript("OnEvent", function(_, _, msg)
        if msg == ERR_MOUNT_SHAPESHIFTED or msg == ERR_NOT_WHILE_SHAPESHIFTED then
            if GetShapeshiftForm() > 0 and not InCombatLockdown() then CancelShapeshiftForm() end
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
                if TransmorpherCharacterState and TransmorpherCharacterState.MountDisplay then
                    ns.savedMountDisplayForVehicle = TransmorpherCharacterState.MountDisplay
                    ns.SendRawMorphCommand("MOUNT_RESET|SUSPEND"); TransmorpherCharacterState.MountDisplay = nil
                else ns.SendRawMorphCommand("SUSPEND") end
            end
        elseif not inVehicle and ns.wasInVehicleLastFrame then
            ns.wasInVehicleLastFrame = false
            if ns.vehicleSuspended then
                ns.vehicleSuspended = false
                if ns.savedMountDisplayForVehicle then
                    TransmorpherCharacterState.MountDisplay = ns.savedMountDisplayForVehicle
                    ns.SendMorphCommand("MOUNT_MORPH:"..ns.savedMountDisplayForVehicle.."|RESUME")
                    ns.savedMountDisplayForVehicle = nil; ns.UpdateSpecialSlots()
                else ns.SendRawMorphCommand("RESUME") end
            end
        end
    end)
end
