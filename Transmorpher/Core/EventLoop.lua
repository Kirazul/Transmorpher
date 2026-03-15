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

-- State tracking
local lastKnownForm = -1
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
-- FORM & BUFF CHECK
-- ============================================================
ns.currentFormMorph = nil
ns.formMorphRuntimeActive = false
local lastFormMorphApplyAt = 0

-- Logic for scheduling rechecks removed to favor single-shot application events.
local function ScheduleFormRecheck(duration, interval)
    -- No-op for cleanup
end

local function StartFormMorph(displayID)
    if not displayID then return end
    -- Apply morph once
    ApplyTemporaryFormMorph(displayID)
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
    end
end

function ns.CheckFormMorphs(forceApply)
    -- Vehicle takes absolute priority — kill all form morphing
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
        -- Apply if the morph changed, wasn't active, or we are forcing a fix for a model slip
        if morphChanged or not ns.formMorphRuntimeActive or forceApply then
            ApplyTemporaryFormMorph(newMorph)
        end
        ns.currentFormMorph = newMorph
        ns.formMorphRuntimeActive = true
        if ns.BroadcastMorphState and morphChanged then ns.BroadcastMorphState(true) end
        return
    end

    -- No form morph needed — clean up
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

        ScheduleMorphSend(0.4)
        ns.RestoreMorphedUI()

        local settings = ns.GetSettings()
        local syncActive = settings.enableWorldSync
        if ns.P2PSetEnabled then
            ns.P2PSetEnabled(syncActive)
        end
        if syncActive and ns.BroadcastMorphState then
            ns.BroadcastMorphState(true)
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        lastKnownForm = GetShapeshiftForm()
        lastKnownMounted = IsMounted() or false
        
        -- Staggered form check for speed and safety
        ns.TimerAfter(0.5, function()
            ns.CheckFormMorphs()
            ScheduleFormRecheck(0.8, 0.06)
        end)

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
                ScheduleMorphSend(0.3) -- More responsive (300ms) but still gives breathing room
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
        
        if ns.BroadcastMorphState then ns.BroadcastMorphState(true) end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        -- Environmental trigger handled by MountManager
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        local currentForm = GetShapeshiftForm()
        if currentForm == lastKnownForm then return end
        lastKnownForm = currentForm
        
        -- 1. Instant Apply
        ns.CheckFormMorphs(true)
        
        -- 2. Safety Window: Re-apply 200ms later to handle slow model loading
        ns.TimerAfter(0.2, function()
            ns.CheckFormMorphs(true)
        end)
        
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
        
        -- Instant Correction with Throttle: If the game resets our model while in form, fix it instantly.
        -- Throttle to 1.5s to avoid the 'infinite loop flickering' caused by the morph itself triggering this event.
        if GetShapeshiftForm() > 0 then
            local now = GetTime()
            lastFormFixAt = lastFormFixAt or 0
            if (now - lastFormFixAt) > 1.5 then
                lastFormFixAt = now
                ns.CheckFormMorphs(true)
            end
        end
        
        local curMounted = IsMounted() or false
        if curMounted ~= lastKnownMounted then
            lastKnownMounted = curMounted
            -- Handled by MountManager.lua
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
