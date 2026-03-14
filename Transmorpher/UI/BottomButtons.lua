local addon, ns = ...

-- ============================================================
-- BOTTOM BUTTONS — Apply All, Reset Morph, Reset Preview, Undress
-- ============================================================

local mainFrame = ns.mainFrame

-- ============================================================
-- SMOOTH HOVER ANIMATION SYSTEM
-- ============================================================
local hoverAnimFrame = CreateFrame("Frame")
hoverAnimFrame:Hide()
local hoverTargets = {}
local btnRestStates = {}

hoverAnimFrame:SetScript("OnUpdate", function(self, dt)
    local t = math.min(dt * 10, 1)
    local anyActive = false
    for btn, info in pairs(hoverTargets) do
        local done = true
        for i = 1, 4 do
            local diff = info.tBg[i] - info.cBg[i]
            if math.abs(diff) > 0.002 then
                info.cBg[i] = info.cBg[i] + diff * t
                done = false
            else
                info.cBg[i] = info.tBg[i]
            end
        end
        for i = 1, 4 do
            local diff = info.tBd[i] - info.cBd[i]
            if math.abs(diff) > 0.002 then
                info.cBd[i] = info.cBd[i] + diff * t
                done = false
            else
                info.cBd[i] = info.tBd[i]
            end
        end
        btn:SetBackdropColor(info.cBg[1], info.cBg[2], info.cBg[3], info.cBg[4])
        btn:SetBackdropBorderColor(info.cBd[1], info.cBd[2], info.cBd[3], info.cBd[4])
        if done then
            hoverTargets[btn] = nil
        else
            anyActive = true
        end
    end
    if not anyActive then self:Hide() end
end)

function ns.RegisterSmoothHover(btn, restBg, restBd)
    btnRestStates[btn] = { bg = {restBg[1], restBg[2], restBg[3], restBg[4]}, bd = {restBd[1], restBd[2], restBd[3], restBd[4]} }
end

function ns.SmoothBackdropTo(btn, targetBg, targetBd)
    local info = hoverTargets[btn]
    if not info then
        local rest = btnRestStates[btn]
        local sBg = rest and rest.bg or {targetBg[1], targetBg[2], targetBg[3], targetBg[4]}
        local sBd = rest and rest.bd or {targetBd[1], targetBd[2], targetBd[3], targetBd[4]}
        info = { cBg = {sBg[1], sBg[2], sBg[3], sBg[4]}, cBd = {sBd[1], sBd[2], sBd[3], sBd[4]} }
        hoverTargets[btn] = info
    end
    info.tBg = targetBg
    info.tBd = targetBd
    hoverAnimFrame:Show()
end

-- Reusable timer frame for Apply All unlock delay
local applyAllUnlockFrame = CreateFrame("Frame")
applyAllUnlockFrame:Hide()
applyAllUnlockFrame.elapsed = 0

-- Apply All
mainFrame.buttons.applyAll = ns.CreateGoldenButton("$parentButtonApplyAll", mainFrame)
do
    local btn = mainFrame.buttons.applyAll
    btn:SetPoint("TOPLEFT", mainFrame.dressingRoom, "BOTTOMLEFT")
    btn:SetPoint("BOTTOM", mainFrame.stats, "BOTTOM", 0, 1)
    btn:SetWidth(mainFrame.dressingRoom:GetWidth()/4)
    btn:SetText("|cffF5C842Apply All|r")
    btn:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=false, tileSize=16, edgeSize=12, insets={left=2,right=2,top=2,bottom=2}})
    btn:SetBackdropColor(0.12, 0.22, 0.10, 0.9)
    btn:SetBackdropBorderColor(0.4, 0.6, 0.25, 1)
    ns.RegisterSmoothHover(btn, {0.12, 0.22, 0.10, 0.9}, {0.4, 0.6, 0.25, 1})

    btn:SetScript("OnClick", function()
        if not ns.IsMorpherReady() then return end
        if ns._applyAllBusy then return end
        local didChange = false
        local cmdQueue = {}
        local state = TransmorpherCharacterState or {}
        local stateItems = state.Items or {}
        local stateHidden = state.HiddenItems or {}
        ns._applyAllBusy = true
        btn:Disable()
        for _, slotName in ipairs(ns.slotOrder) do
            local slot = mainFrame.slots[slotName]
            if slot.itemId and ns.slotToEquipSlotId[slotName] then
                local slotId = ns.slotToEquipSlotId[slotName]
                local trackedItem = stateItems[slotId]
                local trackedHidden = stateHidden[slotId]
                if slot.isHiddenSlot then
                    if not trackedHidden then
                        table.insert(cmdQueue, "ITEM:"..slotId..":-1")
                        local keepItemId = (trackedItem and trackedItem > 0) and trackedItem or ((slot.morphedItemId and slot.morphedItemId > 0) and slot.morphedItemId or slot.itemId)
                        slot.isMorphed = true; slot.morphedItemId = keepItemId
                        ns.FlashMorphSlot(slot)
                        didChange = true
                    end
                else
                    local equippedId = ns.GetEquippedItemForSlot(slotName)
                    if equippedId and equippedId == slot.itemId then
                        slot.isMorphed = false; slot.morphedItemId = nil
                        ns.HideMorphGlow(slot)
                    elseif trackedItem and trackedItem == slot.itemId and not trackedHidden then
                    else
                        table.insert(cmdQueue, "ITEM:"..slotId..":"..slot.itemId)
                        slot.isMorphed = true; slot.morphedItemId = slot.itemId
                        ns.FlashMorphSlot(slot)
                        didChange = true
                    end
                end
            end
        end
        if mainFrame.enchantSlots then
            local mh = mainFrame.enchantSlots["Enchant MH"]
            if mh then
                if mh.enchantId then
                    if state.EnchantMH ~= mh.enchantId then
                        table.insert(cmdQueue, "ENCHANT_MH:"..mh.enchantId)
                        didChange = true
                        mh.isMorphed = true
                        ns.FlashMorphSlot(mh, "orange")
                    end
                else
                    if mh.isMorphed then
                        table.insert(cmdQueue, "ENCHANT_RESET_MH")
                        didChange = true
                        ns.FlashMorphSlot(mh, "orange")
                    end
                    mh.isMorphed = false
                    ns.HideMorphGlow(mh)
                end
            end
            local oh = mainFrame.enchantSlots["Enchant OH"]
            if oh then
                if oh.enchantId then
                    if state.EnchantOH ~= oh.enchantId then
                        table.insert(cmdQueue, "ENCHANT_OH:"..oh.enchantId)
                        didChange = true
                        oh.isMorphed = true
                        ns.FlashMorphSlot(oh, "orange")
                    end
                else
                    if oh.isMorphed then
                        table.insert(cmdQueue, "ENCHANT_RESET_OH")
                        didChange = true
                        ns.FlashMorphSlot(oh, "orange")
                    end
                    oh.isMorphed = false
                    ns.HideMorphGlow(oh)
                end
            end
        end
        if #cmdQueue > 0 then
            ns.SendMorphCommand(table.concat(cmdQueue, "|"))
        end
        if didChange and ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05) end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.08, function()
                ns._applyAllBusy = false
                if btn and btn.Enable then btn:Enable() end
            end)
        else
            applyAllUnlockFrame.elapsed = 0
            applyAllUnlockFrame:SetScript("OnUpdate", function(self, dt)
                self.elapsed = self.elapsed + dt
                if self.elapsed < 0.08 then return end
                self:Hide()
                ns._applyAllBusy = false
                if btn and btn.Enable then btn:Enable() end
            end)
            applyAllUnlockFrame:Show()
        end
        if didChange then
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: All slots morphed!")
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Nothing to apply.")
        end
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        ns.SmoothBackdropTo(self, {0.18, 0.30, 0.14, 0.95}, {0.55, 0.75, 0.35, 1})
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT"); GameTooltip:ClearLines()
        GameTooltip:AddLine("|cffF5C842Apply All|r", 1, 1, 1)
        GameTooltip:AddLine("Apply all previewed items as morph to your character.", 0.7, 0.9, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        ns.SmoothBackdropTo(self, {0.12, 0.22, 0.10, 0.9}, {0.4, 0.6, 0.25, 1})
        GameTooltip:Hide()
    end)
end

-- Reset Morph
mainFrame.buttons.resetMorph = ns.CreateGoldenButton("$parentButtonResetMorph", mainFrame)
do
    local btn = mainFrame.buttons.resetMorph
    btn:SetPoint("TOPLEFT", mainFrame.buttons.applyAll, "TOPRIGHT")
    btn:SetPoint("BOTTOM", mainFrame.buttons.applyAll, "BOTTOM")
    btn:SetWidth(mainFrame.buttons.applyAll:GetWidth())
    btn:SetText("|cffF5C842Reset Morph|r")
    btn:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=false, tileSize=16, edgeSize=12, insets={left=2,right=2,top=2,bottom=2}})
    btn:SetBackdropColor(0.12, 0.10, 0.06, 0.9)
    btn:SetBackdropBorderColor(0.65, 0.52, 0.20, 1)
    ns.RegisterSmoothHover(btn, {0.12, 0.10, 0.06, 0.9}, {0.65, 0.52, 0.20, 1})

    btn:SetScript("OnClick", function()
        if ns.IsMorpherReady() then
            ns.SendMorphCommand("RESET:ALL")
            -- Clear mount morphs
            if TransmorpherCharacterState then
                TransmorpherCharacterState.GroundMountDisplay = nil
                TransmorpherCharacterState.GroundMountName = nil
                TransmorpherCharacterState.FlyingMountDisplay = nil
                TransmorpherCharacterState.FlyingMountName = nil
                TransmorpherCharacterState.MountDisplay = nil
                TransmorpherCharacterState.MountHidden = false
                if TransmorpherCharacterState.Mounts then
                    wipe(TransmorpherCharacterState.Mounts)
                end
            end
            ns.SendRawMorphCommand("MOUNT_RESET")
            for _, slotName in pairs(ns.slotOrder) do
                local slot = mainFrame.slots[slotName]
                slot.isMorphed = false; slot.morphedItemId = nil; slot.isHiddenSlot = false
                ns.HideMorphGlow(slot)
                if slot.eyeButton then
                    slot.eyeButton.isHidden = false
                    if slot.eyeButton.UpdateVisuals then
                        slot.eyeButton:UpdateVisuals()
                    end
                end
                if slotName == ns.rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(ns.playerClass) then
                    -- skip
                else
                    local equippedId = ns.GetEquippedItemForSlot(slotName)
                    if equippedId then slot:SetItem(equippedId)
                    else slot.itemId = nil; slot.textures.empty:Show(); slot.textures.item:Hide() end
                end
            end
            if mainFrame.enchantSlots then
                for _, es in pairs(mainFrame.enchantSlots) do
                    es.isMorphed = false; es:RemoveEnchant(); ns.HideMorphGlow(es)
                end
            end
            ns.SyncDressingRoom()
            if ns.BroadcastMorphState then
                ns.BroadcastMorphState(true)
            end
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: All morphs reset!")
        end
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        ns.SmoothBackdropTo(self, {0.18, 0.15, 0.08, 0.95}, {0.85, 0.68, 0.28, 1})
    end)
    btn:HookScript("OnLeave", function(self)
        ns.SmoothBackdropTo(self, {0.12, 0.10, 0.06, 0.9}, {0.65, 0.52, 0.20, 1})
    end)
end

-- Reset Preview
mainFrame.buttons.reset = ns.CreateGoldenButton("$parentButtonReset", mainFrame)
do
    local btn = mainFrame.buttons.reset
    btn:SetPoint("TOPLEFT", mainFrame.buttons.resetMorph, "TOPRIGHT")
    btn:SetPoint("BOTTOM", mainFrame.buttons.applyAll, "BOTTOM")
    btn:SetWidth(mainFrame.buttons.applyAll:GetWidth())
    btn:SetText("|cff8CB4D8Reset Preview|r")
    btn:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=false, tileSize=16, edgeSize=12, insets={left=2,right=2,top=2,bottom=2}})
    btn:SetBackdropColor(0.08, 0.12, 0.20, 0.9)
    btn:SetBackdropBorderColor(0.3, 0.42, 0.6, 1)
    ns.RegisterSmoothHover(btn, {0.08, 0.12, 0.20, 0.9}, {0.3, 0.42, 0.6, 1})
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:Reset(); PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self) ns.SmoothBackdropTo(self, {0.12, 0.18, 0.28, 0.95}, {0.4, 0.55, 0.8, 1}) end)
    btn:HookScript("OnLeave", function(self) ns.SmoothBackdropTo(self, {0.08, 0.12, 0.20, 0.9}, {0.3, 0.42, 0.6, 1}) end)
end

-- Undress
mainFrame.buttons.undress = ns.CreateGoldenButton("$parentButtonUndress", mainFrame)
do
    local btn = mainFrame.buttons.undress
    btn:SetPoint("TOPLEFT", mainFrame.buttons.reset, "TOPRIGHT")
    btn:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "BOTTOMRIGHT")
    btn:SetPoint("BOTTOM", mainFrame.buttons.applyAll, "BOTTOM")
    btn:SetText("|cffF5C842Undress|r")
    btn:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=false, tileSize=16, edgeSize=12, insets={left=2,right=2,top=2,bottom=2}})
    btn:SetBackdropColor(0.18, 0.13, 0.06, 0.9)
    btn:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
    ns.RegisterSmoothHover(btn, {0.18, 0.13, 0.06, 0.9}, {0.55, 0.45, 0.2, 1})
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:Undress(); PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self) ns.SmoothBackdropTo(self, {0.25, 0.18, 0.08, 0.95}, {0.7, 0.58, 0.3, 1}) end)
    btn:HookScript("OnLeave", function(self) ns.SmoothBackdropTo(self, {0.18, 0.13, 0.06, 0.9}, {0.55, 0.45, 0.2, 1}) end)
end
