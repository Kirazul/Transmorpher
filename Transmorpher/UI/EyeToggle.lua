local addon, ns = ...

local mainFrame = ns.mainFrame
local TOGGLE_SIZE = 15
local TEX_HIDE = "Interface\\AddOns\\Transmorpher\\assets\\Transmog-Overlay-Hide"
local TEX_RESTORE = "Interface\\AddOns\\Transmorpher\\assets\\Transmog-Overlay-Restore"

local function CreateEyeButton(slot, isSpecial)
    local slotName = slot.slotName
    local eyeBtn = CreateFrame("Button", nil, slot)
    eyeBtn:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    eyeBtn:SetFrameLevel(slot:GetFrameLevel() + 5)
    eyeBtn:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 2, 2)
    eyeBtn:RegisterForClicks("AnyUp")

    local icon = eyeBtn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", eyeBtn, "TOPLEFT", 0, 0)
    icon:SetPoint("BOTTOMRIGHT", eyeBtn, "BOTTOMRIGHT", 0, 0)
    icon:SetTexture(TEX_HIDE)
    eyeBtn.icon = icon

    local hl = eyeBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.8)

    if isSpecial and slotName == "Mount" then
        eyeBtn.isHidden = TransmorpherCharacterState and TransmorpherCharacterState.MountHidden or false
    else
        local eqId = ns.slotToEquipSlotId[slotName]
        local stateHidden = TransmorpherCharacterState and TransmorpherCharacterState.HiddenItems and eqId and TransmorpherCharacterState.HiddenItems[eqId]
        local stateItem = TransmorpherCharacterState and TransmorpherCharacterState.Items and eqId and TransmorpherCharacterState.Items[eqId]
        eyeBtn.isHidden = stateHidden or stateItem == -1 or slot.isHiddenSlot == true
    end
    eyeBtn.slotName = slotName
    eyeBtn.isSpecial = isSpecial

    eyeBtn.UpdateVisuals = function(self)
        if self.isHidden then
            self.icon:SetTexture(TEX_RESTORE)
            self.icon:SetVertexColor(1, 1, 1, 1)
        else
            self.icon:SetTexture(TEX_HIDE)
            self.icon:SetVertexColor(1, 1, 1, 1)
        end
        self:SetAlpha(1)
    end

    eyeBtn.UpdateTooltip = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.isHidden then
            GameTooltip:SetText("|T" .. TEX_RESTORE .. ":16:16|t " .. self.slotName .. ": |cffd676ffHidden|r")
            GameTooltip:AddLine("Click to show this slot", 0.7, 0.7, 0.7)
        else
            GameTooltip:SetText("|T" .. TEX_HIDE .. ":16:16|t " .. self.slotName .. ": |cff6bc7ffVisible|r")
            GameTooltip:AddLine("Click to hide this slot", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end

    eyeBtn:SetScript("OnClick", function(self)
        local parentSlot = slot
        if not ns.IsMorpherReady() then return end

        if not self.isHidden then
            if self.isSpecial then
                if self.slotName == "Mount" then
                    if not TransmorpherCharacterState then TransmorpherCharacterState = {Items={}} end
                    TransmorpherCharacterState.MountHidden = true
                    parentSlot.isHiddenSlot = true
                    ns.UpdateSpecialSlots()
                    ns.SendFullMorphState()
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Mount hidden!")
                end
            else
                local equipSlotId = ns.slotToEquipSlotId[self.slotName]
                if equipSlotId then
                    if not TransmorpherCharacterState then TransmorpherCharacterState = {Items={}, HiddenItems={}} end
                    if not TransmorpherCharacterState.Items then TransmorpherCharacterState.Items = {} end
                    if not TransmorpherCharacterState.HiddenItems then TransmorpherCharacterState.HiddenItems = {} end
                    local keepItemId = nil
                    if parentSlot.morphedItemId and parentSlot.morphedItemId > 0 then
                        keepItemId = parentSlot.morphedItemId
                    elseif parentSlot.itemId and parentSlot.itemId > 0 then
                        keepItemId = parentSlot.itemId
                    else
                        keepItemId = ns.GetEquippedItemForSlot(self.slotName)
                    end
                    if keepItemId and keepItemId > 0 then
                        TransmorpherCharacterState.Items[equipSlotId] = keepItemId
                        parentSlot.morphedItemId = keepItemId
                    end
                    TransmorpherCharacterState.HiddenItems[equipSlotId] = true
                    parentSlot.isHiddenSlot = true
                    parentSlot.isMorphed = true
                    ns.ShowMorphGlow(parentSlot)
                    ns.SendFullMorphState()
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: "..self.slotName.." hidden!")
                end
            end
            self.isHidden = true
            self:UpdateVisuals()
            ns.SyncDressingRoom()
        else
            if self.isSpecial then
                if self.slotName == "Mount" then
                    if not TransmorpherCharacterState then TransmorpherCharacterState = {Items={}} end
                    TransmorpherCharacterState.MountHidden = false
                    if TransmorpherCharacterState.MountDisplay == -1 then
                        TransmorpherCharacterState.MountDisplay = nil
                    end
                    local activeMountSpellID = ns.GetActiveMountSpellID and ns.GetActiveMountSpellID()
                    if activeMountSpellID and TransmorpherCharacterState.Mounts and TransmorpherCharacterState.Mounts[activeMountSpellID] == -1 then
                        TransmorpherCharacterState.Mounts[activeMountSpellID] = nil
                    end
                    parentSlot.isHiddenSlot = false
                    ns.UpdateSpecialSlots()
                    ns.SendFullMorphState()
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Mount appearance restored!")
                end
            else
                local equipSlotId = ns.slotToEquipSlotId[self.slotName]
                if equipSlotId then
                    if TransmorpherCharacterState and TransmorpherCharacterState.HiddenItems then
                        TransmorpherCharacterState.HiddenItems[equipSlotId] = nil
                    end
                    local restoreId = nil
                    if TransmorpherCharacterState and TransmorpherCharacterState.Items and TransmorpherCharacterState.Items[equipSlotId] and TransmorpherCharacterState.Items[equipSlotId] > 0 then
                        restoreId = TransmorpherCharacterState.Items[equipSlotId]
                    elseif parentSlot.morphedItemId and parentSlot.morphedItemId > 0 then
                        restoreId = parentSlot.morphedItemId
                    else
                        restoreId = ns.GetEquippedItemForSlot(self.slotName)
                    end
                    parentSlot.isHiddenSlot = false
                    
                    if restoreId and restoreId > 0 then
                        parentSlot:SetItem(restoreId)
                        parentSlot.isMorphed = true
                        parentSlot.morphedItemId = restoreId
                        ns.ShowMorphGlow(parentSlot)
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: "..self.slotName.." morph restored!")
                    else
                        parentSlot.isMorphed = false
                        parentSlot.morphedItemId = nil
                        ns.HideMorphGlow(parentSlot)
                        local equippedId = ns.GetEquippedItemForSlot(self.slotName)
                        if equippedId then parentSlot:SetItem(equippedId) end
                        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: "..self.slotName.." restored!")
                    end
                    ns.SendFullMorphState()
                end
            end
            self.isHidden = false
            self:UpdateVisuals()
            ns.SyncDressingRoom()
        end
        PlaySound("gsTitleOptionOK")
    end)

    eyeBtn:SetScript("OnEnter", function(self)
        self:UpdateTooltip()
    end)
    eyeBtn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    eyeBtn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
            self.icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 1, -1)
        end
    end)
    eyeBtn:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            self.icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        end
    end)

    eyeBtn:UpdateVisuals()
    slot.eyeButton = eyeBtn
    return eyeBtn
end

for _, slotName in pairs(ns.slotOrder) do
    local slot = mainFrame.slots[slotName]
    if slot and ns.slotToEquipSlotId[slotName] then
        CreateEyeButton(slot, false)
    end
end

-- Mount hide eye buttons removed — ground/flying slots handle mount morphing directly
