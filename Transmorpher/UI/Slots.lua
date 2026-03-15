local addon, ns = ...

-- ============================================================
-- EQUIPMENT SLOTS
-- Creates all 14 equipment slots on the dressing room
-- ============================================================

local mainFrame = ns.mainFrame
mainFrame.slots = {}
mainFrame.selectedSlot = nil

local function slot_OnShiftLeftClick(self)
    if self.itemId then
        local _, link = GetItemInfo(self.itemId)
        if link then
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: "..link.." ("..self.itemId..")")
        else
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Item cannot be used for transmogrification.")
        end
    end
end

local function slot_OnControlLeftClick(self)
    if self.itemId then ns.ShowWowheadURLDialog(self.itemId) end
end

local function slot_OnLeftClick(self)
    local selectedSlot = mainFrame.selectedSlot
    if selectedSlot then selectedSlot:UnlockHighlight() end
    if mainFrame.selectedEnchantSlot then
        mainFrame.selectedEnchantSlot:UnlockHighlight()
        mainFrame.selectedEnchantSlot = nil
    end
    if mainFrame.enchantSlots then
        for _, es in pairs(mainFrame.enchantSlots) do es:UnlockHighlight() end
    end
    if mainFrame.tabs.preview.itemsSubTab and mainFrame.tabs.preview.itemsSubTab.enchantMode then
        mainFrame.tabs.preview.itemsSubTab:ExitEnchantMode()
    end
    mainFrame.selectedSlot = self
    if mainFrame.buttons["tab1"] then
        ns.tab_OnClick(mainFrame.buttons["tab1"])
    end
    if mainFrame.tabs.preview.ShowSubTab then
        mainFrame.tabs.preview.ShowSubTab(1)
    end
    if mainFrame.tabs.preview.subclassMenu and mainFrame.tabs.preview.subclassMenu.Update then
        mainFrame.tabs.preview.subclassMenu:Update(self.slotName)
    end
    if self.itemId then
        local found = false
        for subclass, items in pairs(ns.items[self.slotName] or {}) do
            for _, entry in ipairs(items) do
                if entry[1][1] == self.itemId then
                    mainFrame.tabs.preview.itemsSubTab.dropText:SetText(subclass)
                    mainFrame.tabs.preview.itemsSubTab:Update(self.slotName, subclass)
                    found = true
                    break
                end
            end
            if found then break end
        end
        mainFrame.dressingRoom:TryOn(self.itemId)
    end
    self:LockHighlight()
end

local function slot_OnRightClick(self) self:RemoveItem() end

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
    elseif not self.itemId then
        GameTooltip:AddLine(self.slotName)
    else
        local _, link = GetItemInfo(self.itemId)
        if not link then
            GameTooltip:AddLine(self.slotName)
            if self.loadFailed then
                GameTooltip:AddLine("Item #"..self.itemId.." (failed to cache)", 0.9, 0.45, 0.45)
            else
                GameTooltip:AddLine("Item #"..self.itemId.." (loading...)", 0.6, 0.6, 0.6)
            end
        else
            GameTooltip:SetHyperlink(link)
        end
        if self.isMorphed then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffF5C842Transmogrified|r", 0.96, 0.78, 0.26)
        else
            local equippedId = ns.GetEquippedItemForSlot(self.slotName)
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
    if self.isMorphed and self.morphedItemId and self.morphedItemId > 0 then
        self:SetItem(self.morphedItemId)
        ns.ShowMorphGlow(self)
        return
    end
    ns.HideMorphGlow(self)
    local equippedId = ns.GetEquippedItemForSlot(self.slotName)
    if equippedId then self:SetItem(equippedId) else self:RemoveItem() end
end

local function slot_RemoveItem(self)
    if self.itemId then
        local wasMorphed = self.isMorphed
        self.isMorphed = false
        self.morphedItemId = nil
        ns.HideMorphGlow(self)
        if wasMorphed and ns.slotToEquipSlotId[self.slotName] then
            local equipSlotId = ns.slotToEquipSlotId[self.slotName]
            local equippedId = ns.GetEquippedItemForSlot(self.slotName)
            if equippedId then
                ns.TrackUnmorphedSlot(equipSlotId, equippedId)
                ns.SendMorphCommand("ITEM:"..equipSlotId..":"..equippedId)
            else
                ns.TrackUnmorphedSlot(equipSlotId, 0)
                ns.SendMorphCommand("ITEM:"..equipSlotId..":0")
            end
            ns.SendMorphCommand("RESET:"..equipSlotId)
        end
        local equippedId = ns.GetEquippedItemForSlot(self.slotName)
        if equippedId then
            self:SetItem(equippedId)
        else
            self.itemId = nil
            self.textures.empty:Show(); self.textures.item:Hide()
        end
        self:GetScript("OnEnter")(self)
        if ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05)
        elseif ns.SyncDressingRoom then ns.SyncDressingRoom() end
    end
end

local function slot_SetItem(self, itemId)
    if not itemId or itemId <= 0 then
        self.itemId = nil
        self.loadFailed = false
        self.textures.empty:Show()
        self.textures.item:Hide()
        return
    end
    self.itemId = itemId
    self.loadFailed = false
    self.isHiddenSlot = false
    if self.eyeButton then
        self.eyeButton.isHidden = false
        if self.eyeButton.UpdateVisuals then
            self.eyeButton:UpdateVisuals()
        end
    end
    self.textures.empty:Hide()
    self.textures.item:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    self.textures.item:Show()
    mainFrame.dressingRoom:TryOn(itemId)
    ns.QueryItem(itemId, function(queriedItemId, success)
        if queriedItemId == self.itemId then
            if success then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(queriedItemId)
                self.loadFailed = false
                self.textures.empty:Hide()
                self.textures.item:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                self.textures.item:Show()
                mainFrame.dressingRoom:TryOn(queriedItemId)
            else
                self.loadFailed = true
                self.textures.empty:Hide()
                self.textures.item:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                self.textures.item:Show()
            end
        end
    end)
end

-- Build all equipment slots
for slotName, texturePath in pairs(ns.slotTextures) do
    local slot = CreateFrame("Button", "$parentSlot"..slotName, mainFrame, "ItemButtonTemplate")
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 1)

    slot:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and IsAltKeyDown() and self.itemId and ns.slotToEquipSlotId[self.slotName] then
            local didChange = false
            local equippedId = ns.GetEquippedItemForSlot(self.slotName)
            if equippedId and equippedId == self.itemId then
                self.isMorphed = false; self.morphedItemId = nil
                ns.HideMorphGlow(self)
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: "..self.slotName.." already equipped.")
            else
                ns.SendMorphCommand("ITEM:"..ns.slotToEquipSlotId[self.slotName]..":"..self.itemId)
                didChange = true
                self.isMorphed = true; self.morphedItemId = self.itemId
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Morphed "..self.slotName.."!")
                ns.FlashMorphSlot(self)
            end
            if didChange then
                local equipSlotId = ns.slotToEquipSlotId[self.slotName]
                if equipSlotId ~= 16 and equipSlotId ~= 17 and equipSlotId ~= 18 then
                    if ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05)
                    elseif ns.SyncDressingRoom then ns.SyncDressingRoom() end
                end
            end
            PlaySound("gsTitleOptionOK"); return
        end
        slot_OnClick(self, button)
    end)

    slot:SetScript("OnEnter", slot_OnEnter)
    slot:SetScript("OnLeave", slot_OnLeave)
    slot.slotName = slotName
    mainFrame.slots[slotName] = slot
    slot.textures = {}
    slot.textures.empty = slot:CreateTexture(nil, "BACKGROUND")
    slot.textures.empty:SetTexture(texturePath); slot.textures.empty:SetAllPoints()
    slot.textures.item = slot:CreateTexture(nil, "BACKGROUND")
    slot.textures.item:SetAllPoints(); slot.textures.item:Hide()
    slot.Reset = slot_Reset
    slot.SetItem = slot_SetItem
    slot.RemoveItem = slot_RemoveItem
end

-- Position slots
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

-- ============================================================
-- HOOKS — Reset/Undress/OnShow sync
-- ============================================================
local defaultSlot = "Head"

local function btnReset_Hook()
    mainFrame.dressingRoom:Undress()
    for _, slot in pairs(mainFrame.slots) do
        if slot.slotName == ns.rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(ns.playerClass) then
            if not slot.isMorphed then slot:RemoveItem() end
        else slot:Reset() end
    end
    for _, slot in pairs(mainFrame.slots) do
        if slot.itemId then mainFrame.dressingRoom:TryOn(slot.itemId) end
    end
    if mainFrame.dressingRoom.shadowformEnabled then mainFrame.dressingRoom:EnableShadowform() end
end

local function btnUndress_Hook()
    for _, slot in pairs(mainFrame.slots) do
        slot.itemId = nil
        slot.textures.empty:Show(); slot.textures.item:Hide()
        ns.HideMorphGlow(slot)
    end
end

local function dressingRoom_OnShow(self)
    self:Reset()
    local hasMorphed = false
    for _, slot in pairs(mainFrame.slots) do
        if slot.isMorphed and slot.morphedItemId then hasMorphed = true; break end
    end
    self:Undress()
    for _, slot in pairs(mainFrame.slots) do
        if slot.itemId then self:TryOn(slot.itemId) end
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
