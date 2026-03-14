local addon, ns = ...

-- ============================================================
-- LOADOUTS TAB — World Class UI Overhaul
-- ============================================================

local mainFrame = ns.mainFrame
local slotOrder = ns.slotOrder
local slotToEquipSlotId = ns.slotToEquipSlotId
local slotTextures = ns.slotTextures or {}

mainFrame.tabs.appearances.saved = CreateFrame("Frame", "$parentSaved", mainFrame.tabs.appearances)
local appearancesTab = mainFrame.tabs.appearances
local frame = appearancesTab.saved

-- Left List Panel
frame:SetPoint("TOPLEFT", 0, -8); frame:SetPoint("BOTTOMLEFT", 0, 8); frame:SetWidth(200)
frame:SetBackdrop({
    bgFile="Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile="Interface\\Buttons\\WHITE8X8",
    tile=false, tileSize=0, edgeSize=1,
    insets={left=1,right=1,top=1,bottom=1}
})
frame:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

-- Title Header
local listTitleBg = frame:CreateTexture(nil, "BACKGROUND")
listTitleBg:SetPoint("TOPLEFT", 1, -1); listTitleBg:SetPoint("TOPRIGHT", -1, -1); listTitleBg:SetHeight(28)
listTitleBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
listTitleBg:SetVertexColor(0.12, 0.10, 0.06, 0.8)

local listTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listTitle:SetPoint("LEFT", listTitleBg, "LEFT", 10, 0)
listTitle:SetText("|cffffd700Saved Loadouts|r")

local listSep = frame:CreateTexture(nil, "OVERLAY")
listSep:SetPoint("TOPLEFT", listTitleBg, "BOTTOMLEFT", 0, 0); listSep:SetPoint("TOPRIGHT", listTitleBg, "BOTTOMRIGHT", 0, 0); listSep:SetHeight(1)
listSep:SetTexture("Interface\\Buttons\\WHITE8X8"); listSep:SetVertexColor(0.3, 0.3, 0.3, 1)

-- Save New Input Area
local newContainer = CreateFrame("Frame", nil, frame)
newContainer:SetPoint("BOTTOMLEFT", 4, 3); newContainer:SetPoint("BOTTOMRIGHT", -4, 3); newContainer:SetHeight(28)
newContainer:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
newContainer:SetBackdropColor(0.03, 0.03, 0.03, 0.9); newContainer:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

local newHint = newContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
newHint:SetPoint("LEFT", 6, 0); newHint:SetText("Save new...")

local newBox = CreateFrame("EditBox", nil, newContainer)
newBox:SetPoint("LEFT", 6, 0); newBox:SetPoint("RIGHT", -26, 0); newBox:SetHeight(20)
newBox:SetFont("Fonts\\FRIZQT__.TTF", 11); newBox:SetTextColor(0.95, 0.88, 0.65)
newBox:SetAutoFocus(false)
newBox:SetScript("OnEditFocusGained", function() newHint:Hide(); newContainer:SetBackdropBorderColor(0.96, 0.78, 0.26, 1) end)
newBox:SetScript("OnEditFocusLost", function(self)
    if self:GetText() == "" then newHint:Show(); newContainer:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end
end)
newBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(""); newHint:Show() end)

local btnAdd = CreateFrame("Button", nil, newContainer)
btnAdd:SetSize(20, 20); btnAdd:SetPoint("RIGHT", -2, 0)
local btnAddIcon = btnAdd:CreateTexture(nil, "OVERLAY")
btnAddIcon:SetAllPoints(); btnAddIcon:SetTexture("Interface\\PaperDollInfoFrame\\Character-Plus")
btnAddIcon:SetVertexColor(0.4, 0.4, 0.4)
btnAdd:SetScript("OnEnter", function() btnAddIcon:SetVertexColor(1, 0.8, 0.2) end)
btnAdd:SetScript("OnLeave", function() btnAddIcon:SetVertexColor(0.4, 0.4, 0.4) end)

-- Scroll Frame for Custom List
local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", frame)
scrollFrame:SetPoint("TOPLEFT", 4, -34); scrollFrame:SetPoint("BOTTOMRIGHT", -4, 36)
local listContent = CreateFrame("Frame", "$parentContent", scrollFrame)
listContent:SetSize(scrollFrame:GetWidth(), 1)
scrollFrame:SetScrollChild(listContent)

scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll(); local mx = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(mx, cur - delta*30)))
end)

-- Right Panel (Preview)
local previewFrame = CreateFrame("Frame", "$parentLoadoutPreview", appearancesTab)
previewFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
previewFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 6, 0)
previewFrame:SetPoint("RIGHT", -6, 0)
previewFrame:SetBackdrop({
    bgFile="Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile="Interface\\Buttons\\WHITE8X8",
    tile=false, tileSize=0, edgeSize=1,
    insets={left=1,right=1,top=1,bottom=1}
})
previewFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
previewFrame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

-- Right Header
local prevTitleBg = previewFrame:CreateTexture(nil, "BACKGROUND")
prevTitleBg:SetPoint("TOPLEFT", 1, -1); prevTitleBg:SetPoint("TOPRIGHT", -1, -1); prevTitleBg:SetHeight(40)
prevTitleBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
prevTitleBg:SetVertexColor(0.12, 0.10, 0.06, 0.8)

local prevSep = previewFrame:CreateTexture(nil, "OVERLAY")
prevSep:SetPoint("TOPLEFT", prevTitleBg, "BOTTOMLEFT", 0, 0); prevSep:SetPoint("TOPRIGHT", prevTitleBg, "BOTTOMRIGHT", 0, 0); prevSep:SetHeight(1)
prevSep:SetTexture("Interface\\Buttons\\WHITE8X8"); prevSep:SetVertexColor(0.3, 0.3, 0.3, 1)

local loadoutNameLabel = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
loadoutNameLabel:SetPoint("LEFT", prevTitleBg, "LEFT", 14, 6); loadoutNameLabel:SetText("|cff8a7d6aNo Loadout Selected|r")
local loadoutSubLabel = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
loadoutSubLabel:SetPoint("TOPLEFT", loadoutNameLabel, "BOTTOMLEFT", 1, -2); loadoutSubLabel:SetText("Previewing appearances...")
loadoutSubLabel:SetTextColor(0.5, 0.5, 0.5)

local btnUpdate = ns.CreateGoldenButton("$parentButtonUpdate", previewFrame)
btnUpdate:SetSize(90, 24); btnUpdate:SetPoint("RIGHT", prevTitleBg, "RIGHT", -12, 0)
btnUpdate:SetText("Overwrite"); btnUpdate:Disable()

-- Dressing room
local previewModel = CreateFrame("DressUpModel", "$parentPreviewModel", previewFrame)
previewModel:SetPoint("TOP", 0, -42)
previewModel:SetPoint("BOTTOM", 0, 108)
previewModel:SetWidth(200)
previewModel:SetUnit("player"); previewModel:SetFacing(-0.4); previewModel:SetPosition(0, 0, 0)

-- FULL SECTION BACKDROP (covers the entire right panel)
local modelBg = previewFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
modelBg:SetPoint("TOPLEFT", 1, -41)
modelBg:SetPoint("BOTTOMRIGHT", -1, 1)
modelBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
modelBg:SetVertexColor(0.04, 0.04, 0.04, 0.6)


-- Lines removed as per user request

-- Smooth zooming & rotation
previewModel:EnableMouseWheel(true)
local zoomTarget, zoomCurrent = 0, 0
previewModel:SetScript("OnMouseWheel", function(self, delta)
    zoomTarget = math.max(-2, math.min(4, zoomTarget + delta * 0.4))
end)

local previewRotating = false
previewModel:EnableMouse(true)
previewModel:SetScript("OnMouseDown", function(_, b) if b == "LeftButton" then previewRotating = true end end)
previewModel:SetScript("OnMouseUp", function(_, b) if b == "LeftButton" then previewRotating = false end end)
previewModel:SetScript("OnUpdate", function(self, dt)
    if previewRotating and IsMouseButtonDown("LeftButton") then
        local x = GetCursorPosition() / UIParent:GetEffectiveScale()
        if self.lastX then self:SetFacing(self:GetFacing() + (x - self.lastX) * 0.02) end
        self.lastX = x
    else self.lastX = nil end
    
    if math.abs(zoomTarget - zoomCurrent) > 0.01 then
        zoomCurrent = zoomCurrent + (zoomTarget - zoomCurrent) * 10 * dt
        local x,y,z = self:GetPosition(); self:SetPosition(zoomCurrent, y, z)
    end
end)

-- Big Apply Button Bottom Center
local btnApplyLoadout = ns.CreateGoldenButton("$parentButtonApplyLoadout", previewFrame)
btnApplyLoadout:SetPoint("BOTTOM", 0, 6); btnApplyLoadout:SetSize(360, 28)
btnApplyLoadout:SetText("|cffF5C842Apply Loadout|r"); btnApplyLoadout:Disable()

-- Preview Grid Setup (EQUIPMENT)
local previewSlots = {}
local function CreateSlot(name, icon, align, pY)
    local s = CreateFrame("Button", "$parentPreview"..name:gsub(" ",""), previewFrame)
    s:SetSize(36, 36)
    if align == "LEFT" then s:SetPoint("TOPLEFT", 20, pY) else s:SetPoint("TOPRIGHT", -20, pY) end
    s:SetNormalTexture(icon); s:GetNormalTexture():SetTexCoord(0.1, 0.9, 0.1, 0.9)
    
    local itemTex = s:CreateTexture(nil, "OVERLAY"); itemTex:SetAllPoints(); itemTex:SetTexCoord(0.08,0.92,0.08,0.92); itemTex:Hide(); s.itemTex = itemTex
    s:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1}); s:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    s.slotName = name; s:EnableMouse(true)
    
    s:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemId and self.itemId > 0 then
            GameTooltip:SetHyperlink("item:"..self.itemId)
        else
            GameTooltip:SetText(self.slotName, 1, 1, 1)
            GameTooltip:AddLine("Empty Slot", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1); GameTooltip:Hide() end)
    return s
end

local sY = -50
local sp = -42
previewSlots["Head"] = CreateSlot("Head", slotTextures["Head"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Head", "LEFT", sY)
previewSlots["Shoulder"] = CreateSlot("Shoulder", slotTextures["Shoulder"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Shoulder", "LEFT", sY + sp)
previewSlots["Back"] = CreateSlot("Back", slotTextures["Back"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Chest", "LEFT", sY + sp*2) -- standard uses chest texture for back empty usually
previewSlots["Chest"] = CreateSlot("Chest", slotTextures["Chest"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Chest", "LEFT", sY + sp*3)
previewSlots["Shirt"] = CreateSlot("Shirt", slotTextures["Shirt"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Shirt", "LEFT", sY + sp*4)
previewSlots["Tabard"] = CreateSlot("Tabard", slotTextures["Tabard"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Tabard", "LEFT", sY + sp*5)
previewSlots["Wrist"] = CreateSlot("Wrist", slotTextures["Wrist"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Wrists", "LEFT", sY + sp*6)

previewSlots["Hands"] = CreateSlot("Hands", slotTextures["Hands"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Hands", "RIGHT", sY)
previewSlots["Waist"] = CreateSlot("Waist", slotTextures["Waist"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Waist", "RIGHT", sY + sp)
previewSlots["Legs"] = CreateSlot("Legs", slotTextures["Legs"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Legs", "RIGHT", sY + sp*2)
previewSlots["Feet"] = CreateSlot("Feet", slotTextures["Feet"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-Feet", "RIGHT", sY + sp*3)
previewSlots["Main Hand"] = CreateSlot("Main Hand", slotTextures["Main Hand"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-MainHand", "RIGHT", sY + sp*4)
previewSlots["Off-hand"] = CreateSlot("Off-hand", slotTextures["Off-hand"] or "Interface\\Paperdoll\\UI-PaperDoll-Slot-SecondaryHand", "RIGHT", sY + sp*5)

-- Special / Enchants (placed horizontally below everything)
local function CreateSpecSlot(name, icon, pxOffset)
    local s = CreateFrame("Button", "$parentPreviewS"..name:gsub(" ",""), previewFrame)
    s:SetSize(26, 26)
    s:SetPoint("BOTTOM", pxOffset, 68)
    s:SetNormalTexture(icon); s:GetNormalTexture():SetTexCoord(0.1, 0.9, 0.1, 0.9)
    s:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1}); s:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    local bg = s:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(0,0,0,0.8)
    
    local lb = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); lb:SetPoint("TOP", s, "BOTTOM", 0, -2); lb:SetTextColor(0.6,0.6,0.6); lb:SetText(name); s.label = lb
    
    local sl = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); sl:SetPoint("TOP", lb, "BOTTOM", 0, -2); sl:SetTextColor(0.8, 0.8, 0.8); sl:Hide(); s.scaleLabel = sl
    
    s.slotName = name; s:EnableMouse(true)
    
    s:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.slotName, 1, 1, 1)
        if self.displayId then
            GameTooltip:AddLine("ID: "..self.displayId, 1, 0.8, 0)
        else
            GameTooltip:AddLine("None selected", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1); GameTooltip:Hide() end)
    return s
end

-- Layout horizontally in center
previewSlots["Mount"] = CreateSpecSlot("Mount", "Interface\\Icons\\Ability_Mount_RidingHorse", -125)
previewSlots["Pet"] = CreateSpecSlot("Pet", "Interface\\Icons\\INV_Box_PetCarrier_01", -75)
previewSlots["Combat Pet"] = CreateSpecSlot("C.Pet", "Interface\\Icons\\Ability_Hunter_BeastCall", -25)
previewSlots["Morph Form"] = CreateSpecSlot("Morph", "Interface\\Icons\\Spell_Shadow_Charm", 25)
previewSlots["Enchant MH"] = CreateSpecSlot("Enc.MH", "Interface\\Icons\\INV_Enchant_EssenceMagicLarge", 75)
previewSlots["Enchant OH"] = CreateSpecSlot("Enc.OH", "Interface\\Icons\\INV_Enchant_EssenceMagicLarge", 125)

-- ============================================================
-- List System & Data Logic
-- ============================================================
local loadoutButtons = {}
local selectedLoadoutId = nil
local activeLookId = "CURRENT"

local function CaptureCurrentLoadout(...)
    local loadout = {items={}, hiddenSlots={}, enchantMH=nil, enchantOH=nil, mountDisplay=nil, mountHidden=false, petDisplay=nil, combatPetDisplay=nil, combatPetScale=nil, morphForm=nil, morphScale=nil, titleID=nil}
    for index, slotName in ipairs(slotOrder) do
        local slot = mainFrame.slots[slotName]
        if slot and slot.isHiddenSlot then
            loadout.items[index] = -1
            loadout.hiddenSlots[index] = true
        else
            loadout.items[index] = (slot and slot.morphedItemId and slot.morphedItemId > 0 and slot.morphedItemId) or (slot and slot.itemId) or 0
        end
    end
    if mainFrame.enchantSlots and mainFrame.enchantSlots["Enchant MH"] and mainFrame.enchantSlots["Enchant MH"].enchantId then loadout.enchantMH = mainFrame.enchantSlots["Enchant MH"].enchantId end
    if mainFrame.enchantSlots and mainFrame.enchantSlots["Enchant OH"] and mainFrame.enchantSlots["Enchant OH"].enchantId then loadout.enchantOH = mainFrame.enchantSlots["Enchant OH"].enchantId end
    if TransmorpherCharacterState then
        loadout.mountDisplay = TransmorpherCharacterState.MountDisplay
        loadout.mountHidden = TransmorpherCharacterState.MountHidden or false
        loadout.petDisplay = TransmorpherCharacterState.PetDisplay
        loadout.mounts = {}
        if TransmorpherCharacterState.Mounts then
            for k, v in pairs(TransmorpherCharacterState.Mounts) do loadout.mounts[k] = v end
        end
        if TransmorpherCharacterState.HunterPetDisplay then loadout.combatPetDisplay = TransmorpherCharacterState.HunterPetDisplay; loadout.combatPetScale = TransmorpherCharacterState.HunterPetScale end
        if TransmorpherCharacterState.Morph then loadout.morphForm = TransmorpherCharacterState.Morph; loadout.morphScale = TransmorpherCharacterState.MorphScale end
        loadout.titleID = TransmorpherCharacterState.TitleID
    end
    return loadout
end

local lookTimer = CreateFrame("Frame"); lookTimer:Hide()
local function UpdateLoadoutPreview(loadout)
    lookTimer:Hide(); lookTimer:SetScript("OnUpdate", nil)
    if not loadout then
        loadoutNameLabel:SetText("|cff8a7d6aSelect a loadout|r")
        loadoutSubLabel:SetText("")
        previewModel:SetUnit("player"); previewModel:Undress()
        modelBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        modelBg:SetVertexColor(0.03, 0.03, 0.03, 0.8)
        for _, s in pairs(previewSlots) do
            if s.itemTex then s.itemTex:Hide() end
            if s.label then
                local lbl = s.slotName
                s.label:SetText(lbl); s.label:SetTextColor(0.6,0.6,0.6)
            end
            s.itemId = nil; s.displayId = nil
        end
        return
    end
    
    
    if loadout.isCurrent then loadoutNameLabel:SetText("|cffffd700Current Equipped Appearance|r") else loadoutNameLabel:SetText("|cffffd700"..(loadout.name or "Loadout").."|r") end
    loadoutSubLabel:SetText("Previewing appearances...")
    previewModel:SetUnit("player"); previewModel:Undress()
    
    local _, raceFileName = UnitRace("player")
    local raceToBgKey = {
        Human="human", NightElf="nightelf", Dwarf="dwarf", Gnome="gnome",
        Draenei="draenei", Orc="orc", Scourge="scourge", Tauren="tauren",
        Troll="troll", BloodElf="bloodelf",
    }
    local bgKey = raceToBgKey[raceFileName] or "human"
    if bgKey == "DEATHKNIGHT" then bgKey = "deathknight" end
    modelBg:SetTexture("Interface\\AddOns\\Transmorpher\\images\\"..bgKey)
    modelBg:SetVertexColor(0.4, 0.4, 0.4, 0.6)
    
    local pending = {}
    local pendingMainHand = nil
    local pendingOffHand = nil
    for index, slotName in ipairs(slotOrder) do
        local itemId = loadout.items and loadout.items[index]
        local s = previewSlots[slotName]
        if s then
            if itemId and itemId ~= 0 then
                s.itemId = itemId
                if slotName == "Main Hand" then
                    pendingMainHand = itemId
                elseif slotName == "Off-hand" then
                    pendingOffHand = itemId
                elseif slotName ~= "Ranged" then
                    table.insert(pending, itemId)
                end
                local _,_,_,_,_,_,_,_,_,tex = GetItemInfo(itemId)
                if tex then s.itemTex:SetTexture(tex); s.itemTex:Show()
                else
                    s.itemTex:Hide()
                    ns.QueryItem(itemId, function(qId, ok) if ok and qId == itemId and s.itemId == qId then local _,_,_,_,_,_,_,_,_,t = GetItemInfo(qId); if t then s.itemTex:SetTexture(t); s.itemTex:Show() end end end)
                end
            else
                s.itemTex:Hide(); s.itemId = nil
            end
        end
    end
    
    local function DressModel()
        for _, id in ipairs(pending) do previewModel:TryOn(id) end
        if pendingOffHand then previewModel:TryOn(pendingOffHand) end
        if pendingMainHand then previewModel:TryOn(pendingMainHand) end
    end
    DressModel()
    
    -- Retry uncached items
    local uc = 0
    for _, id in ipairs(pending) do
        local _,l = GetItemInfo(id)
        if not l then uc = uc + 1; ns.QueryItem(id, nil) end
    end
    if pendingOffHand then
        local _,l = GetItemInfo(pendingOffHand)
        if not l then uc = uc + 1; ns.QueryItem(pendingOffHand, nil) end
    end
    if pendingMainHand then
        local _,l = GetItemInfo(pendingMainHand)
        if not l then uc = uc + 1; ns.QueryItem(pendingMainHand, nil) end
    end
    if uc > 0 then
        local rc = 0; lookTimer.elapsed = 0
        lookTimer:SetScript("OnUpdate", function(self, dt) self.elapsed = self.elapsed + dt
            if self.elapsed >= 0.1 then self.elapsed = 0; rc = rc + 1
                local all = true
                for _, id in ipairs(pending) do
                    local _,l = GetItemInfo(id)
                    if not l then all = false; break end
                end
                if all and pendingOffHand then
                    local _,l = GetItemInfo(pendingOffHand)
                    if not l then all = false end
                end
                if all and pendingMainHand then
                    local _,l = GetItemInfo(pendingMainHand)
                    if not l then all = false end
                end
                if all or rc >= 15 then DressModel(); self:Hide(); self:SetScript("OnUpdate", nil) end
            end
        end); lookTimer:Show()
    end

    -- Apply glows to equipment preview slots
    for _, slotName in ipairs(slotOrder) do
        local s = previewSlots[slotName]
        if s then
            if s.itemId and s.itemId ~= 0 then
                ns.ShowMorphGlow(s, "gold")
            else
                ns.HideMorphGlow(s)
            end
        end
    end
    
    -- Special labels
    local function UpdSpec(name, data, glowColor, r, g, b)
        local s = previewSlots[name]
        if data and data > 0 then 
            s.label:SetText(data); s.label:SetTextColor(r,g,b); s.displayId = data
            ns.ShowMorphGlow(s, glowColor)
        else 
            s.label:SetText(s.slotName); s.label:SetTextColor(0.4,0.4,0.4); s.displayId = nil 
            ns.HideMorphGlow(s)
        end
    end
    UpdSpec("Mount", loadout.mountDisplay, "red", 1.0, 0.4, 0.4)
    UpdSpec("Pet", loadout.petDisplay, "red", 1.0, 0.4, 0.4)
    UpdSpec("Combat Pet", loadout.combatPetDisplay, "red", 1.0, 0.4, 0.4)
    if loadout.combatPetDisplay and loadout.combatPetDisplay > 0 then
        local petScale = loadout.combatPetScale or 1.0
        previewSlots["Combat Pet"].scaleLabel:SetText(string.format("Scale: %g", petScale))
        previewSlots["Combat Pet"].scaleLabel:SetTextColor(1.0, 0.4, 0.4)
        previewSlots["Combat Pet"].scaleLabel:Show()
    else 
        previewSlots["Combat Pet"].scaleLabel:Hide() 
    end
    
    UpdSpec("Morph Form", loadout.morphForm, "purple", 0.8, 0.5, 1.0)
    if loadout.morphForm and loadout.morphForm > 0 then
        local morphScale = loadout.morphScale or 1.0
        previewSlots["Morph Form"].scaleLabel:SetText(string.format("Scale: %g", morphScale))
        previewSlots["Morph Form"].scaleLabel:SetTextColor(0.8, 0.5, 1.0)
        previewSlots["Morph Form"].scaleLabel:Show() 
    else 
        previewSlots["Morph Form"].scaleLabel:Hide() 
    end
    
    local eMH = previewSlots["Enchant MH"]; 
    if loadout.enchantMH and loadout.enchantMH > 0 then 
        eMH.label:SetText(loadout.enchantMH); eMH.label:SetTextColor(0.6,1,0.6); eMH.displayId=loadout.enchantMH 
        ns.ShowMorphGlow(eMH, "green")
    else 
        eMH.label:SetText("Enc.MH"); eMH.label:SetTextColor(0.4,0.4,0.4); eMH.displayId=nil 
        ns.HideMorphGlow(eMH)
    end
    
    local eOH = previewSlots["Enchant OH"]; 
    if loadout.enchantOH and loadout.enchantOH > 0 then 
        eOH.label:SetText(loadout.enchantOH); eOH.label:SetTextColor(0.6,1,0.6); eOH.displayId=loadout.enchantOH 
        ns.ShowMorphGlow(eOH, "green")
    else 
        eOH.label:SetText("Enc.OH"); eOH.label:SetTextColor(0.4,0.4,0.4); eOH.displayId=nil 
        ns.HideMorphGlow(eOH)
    end
end

local function ApplyLoadout(loadout)
    if not ns.IsMorpherReady() or not loadout or loadout.isCurrent then return end

    PlaySound("LevelUp")
    local state = TransmorpherCharacterState
    local stateItems = (state and state.Items) or {}
    local stateHidden = (state and state.HiddenItems) or {}
    local didChange = false
    local changedMount = false
    local changedPet = false
    local changedCombatPet = false
    local changedMorphForm = false
    local cmdQueue = {}
    local function Enqueue(cmd)
        table.insert(cmdQueue, cmd)
        didChange = true
    end
    local function FlushQueue()
        if #cmdQueue == 0 then return end
        ns.SendMorphCommand(table.concat(cmdQueue, "|"))
        wipe(cmdQueue)
    end

    for index, slotName in ipairs(slotOrder) do
        local itemId = loadout.items and loadout.items[index]
        local isHidden = loadout.hiddenSlots and loadout.hiddenSlots[index]
        local slot = mainFrame.slots[slotName]

        if slot then
            local slotId = slotToEquipSlotId[slotName]
            if isHidden and slotId then
                Enqueue("ITEM:"..slotId..":-1")
                slot.isMorphed = true
                slot.morphedItemId = (itemId and itemId > 0) and itemId or slot.morphedItemId
                slot.isHiddenSlot = true
                ns.FlashMorphSlot(slot, "gold")
                if slot.eyeButton then
                    slot.eyeButton.isHidden = true
                    slot.eyeButton.wasMorphed = false
                    slot.eyeButton.savedMorphId = nil
                    if slot.eyeButton.UpdateVisuals then slot.eyeButton:UpdateVisuals() end
                end
            elseif itemId and itemId > 0 and slotId then
                local equippedId = ns.GetEquippedItemForSlot(slotName)
                local tracked = stateItems[slotId]
                local trackedHidden = stateHidden[slotId]
                if equippedId and equippedId == itemId then
                    if slot.isMorphed or slot.isHiddenSlot or trackedHidden or (tracked and tracked ~= itemId) then
                        Enqueue("RESET:"..slotId)
                    end
                    slot.isMorphed = false; slot.morphedItemId = nil; slot.isHiddenSlot = false; slot:SetItem(itemId); ns.HideMorphGlow(slot)
                else
                    Enqueue("ITEM:"..slotId..":"..itemId)
                    slot.isMorphed = true; slot.morphedItemId = itemId; slot.isHiddenSlot = false; slot:SetItem(itemId)
                    ns.FlashMorphSlot(slot, "gold")
                end
                if slot.eyeButton then
                    slot.eyeButton.isHidden = false
                    if slot.eyeButton.UpdateVisuals then slot.eyeButton:UpdateVisuals() end
                end
            elseif slotId then
                if stateItems[slotId] ~= nil or stateHidden[slotId] or slot.isMorphed or slot.isHiddenSlot then
                    if slotName == "Main Hand" or slotName == "Off-hand" or slotName == "Ranged" then
                        Enqueue("ITEM:"..slotId..":0")
                    else
                        Enqueue("RESET:"..slotId)
                    end
                end

                slot.isMorphed = false; slot.morphedItemId = nil; slot.isHiddenSlot = false
                ns.HideMorphGlow(slot)

                local equippedId = ns.GetEquippedItemForSlot(slotName)
                if equippedId then slot:SetItem(equippedId)
                else slot.itemId = nil; slot.textures.empty:Show(); slot.textures.item:Hide() end
                if slot.eyeButton then
                    slot.eyeButton.isHidden = false
                    if slot.eyeButton.UpdateVisuals then slot.eyeButton:UpdateVisuals() end
                end
            end
        end
    end

    -- Enchants MH
    local eMH = mainFrame.enchantSlots["Enchant MH"]
    if loadout.enchantMH and loadout.enchantMH > 0 then 
        Enqueue("ENCHANT_MH:"..loadout.enchantMH)
        local en = ns.enchantDB and ns.enchantDB[loadout.enchantMH] or tostring(loadout.enchantMH); 
        eMH:SetEnchant(loadout.enchantMH, en); 
        ns.FlashMorphSlot(eMH, "green")
    else
        if eMH.isMorphed or (state and state.EnchantMH) then
            Enqueue("ENCHANT_RESET_MH")
        end
        eMH:RemoveEnchant()
        ns.HideMorphGlow(eMH)
    end

    -- Enchants OH
    local eOH = mainFrame.enchantSlots["Enchant OH"]
    if loadout.enchantOH and loadout.enchantOH > 0 then 
        Enqueue("ENCHANT_OH:"..loadout.enchantOH)
        local en = ns.enchantDB and ns.enchantDB[loadout.enchantOH] or tostring(loadout.enchantOH); 
        eOH:SetEnchant(loadout.enchantOH, en); 
        ns.FlashMorphSlot(eOH, "green")
    else
        if eOH.isMorphed or (state and state.EnchantOH) then
            Enqueue("ENCHANT_RESET_OH")
        end
        eOH:RemoveEnchant()
        ns.HideMorphGlow(eOH)
    end

    -- Mount morph (with hidden support)
    if TransmorpherCharacterState then
        -- Clear existing per-mount morphs first, then load from loadout
        TransmorpherCharacterState.Mounts = {}
        if loadout.mounts then
            for spellID, displayID in pairs(loadout.mounts) do
                TransmorpherCharacterState.Mounts[spellID] = displayID
            end
        end

        if loadout.mountHidden then
            TransmorpherCharacterState.MountHidden = true
            TransmorpherCharacterState.MountDisplay = loadout.mountDisplay
            FlushQueue()
            ns.SendFullMorphState()
            didChange = true
            changedMount = true
        elseif loadout.mountDisplay and loadout.mountDisplay > 0 then
            TransmorpherCharacterState.MountHidden = false
            TransmorpherCharacterState.MountDisplay = loadout.mountDisplay
            Enqueue("MOUNT_MORPH:"..loadout.mountDisplay)
            changedMount = true
        else
            local needsMountReset = state and (state.MountDisplay or state.MountHidden)
            TransmorpherCharacterState.MountHidden = false
            TransmorpherCharacterState.MountDisplay = nil
            if needsMountReset then
                Enqueue("MOUNT_RESET")
                changedMount = true
            end
        end
    end

    if loadout.petDisplay and loadout.petDisplay > 0 then
        Enqueue("PET_MORPH:"..loadout.petDisplay)
        changedPet = true
        if TransmorpherCharacterState then TransmorpherCharacterState.PetDisplay = loadout.petDisplay end
    else
        if state and state.PetDisplay then
            Enqueue("PET_RESET")
            changedPet = true
        end
        if TransmorpherCharacterState then TransmorpherCharacterState.PetDisplay = nil end
    end

    if loadout.combatPetDisplay and loadout.combatPetDisplay > 0 then
        Enqueue("HPET_MORPH:"..loadout.combatPetDisplay)
        changedCombatPet = true
        if TransmorpherCharacterState then TransmorpherCharacterState.HunterPetDisplay = loadout.combatPetDisplay end
        local cs = loadout.combatPetScale or 1.0
        Enqueue("HPET_SCALE:"..cs)
        if TransmorpherCharacterState then TransmorpherCharacterState.HunterPetScale = cs end
    else
        if state and (state.HunterPetDisplay or state.HunterPetScale) then
            Enqueue("HPET_RESET")
            changedCombatPet = true
        end
        if TransmorpherCharacterState then TransmorpherCharacterState.HunterPetDisplay = nil; TransmorpherCharacterState.HunterPetScale = nil end
    end

    if loadout.morphForm and loadout.morphForm > 0 then
        Enqueue("MORPH:"..loadout.morphForm)
        changedMorphForm = true
        if TransmorpherCharacterState then TransmorpherCharacterState.Morph = loadout.morphForm end
        local ms = loadout.morphScale or 1.0
        Enqueue("SCALE:"..ms)
        if TransmorpherCharacterState then TransmorpherCharacterState.MorphScale = ms end
    else
        if state and (state.Morph or state.MorphScale or state.Scale) then
            Enqueue("MORPH:0")
            changedMorphForm = true
        end
        if TransmorpherCharacterState then TransmorpherCharacterState.Morph = nil; TransmorpherCharacterState.MorphScale = nil end
    end

    if loadout.titleID and loadout.titleID > 0 then
        Enqueue("TITLE:"..loadout.titleID)
        if TransmorpherCharacterState then TransmorpherCharacterState.TitleID = loadout.titleID end
    else
        if state and state.TitleID then
            Enqueue("TITLE_RESET")
        end
        if TransmorpherCharacterState then TransmorpherCharacterState.TitleID = nil end
    end

    FlushQueue()
    if didChange and ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05) end
    ns.UpdateSpecialSlots()
    
    -- Add flash to special slots
    local ss = mainFrame.specialSlots
    if ss then
        if changedMount and ss.Mount and ss.Mount.displayID then ns.FlashMorphSlot(ss.Mount, "red") end
        if changedPet and ss.Pet and ss.Pet.displayID then ns.FlashMorphSlot(ss.Pet, "red") end
        if changedCombatPet and ss.CombatPet and ss.CombatPet.displayID then ns.FlashMorphSlot(ss.CombatPet, "red") end
        if changedMorphForm and ss.MorphForm and ss.MorphForm.displayID then ns.FlashMorphSlot(ss.MorphForm, "purple") end
    end

    -- Force a sync broadcast after all loadout items are applied
    if ns.BroadcastMorphState then
        ns.BroadcastMorphState(true)
    end

    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Loadout '"..loadout.name.."' applied!")
end

local function BuildListFrames()
    local saved = _G["TransmorpherLoadoutsAccount"]
    if not saved then return end
    
    for _, btn in ipairs(loadoutButtons) do btn:Hide(); btn.layoutIdx = nil end
    
    local yOff = 0
    local ROW_H = 34
    
    -- Current Equipped
    local curBtn = loadoutButtons[1]
    if not curBtn then
        curBtn = CreateFrame("Button", nil, listContent)
        curBtn:SetSize(listContent:GetWidth() - 4, ROW_H)
        curBtn:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
        curBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square"); curBtn:GetHighlightTexture():SetAlpha(0.1)
        
        local ic = curBtn:CreateTexture(nil, "OVERLAY")
        ic:SetSize(22, 22); ic:SetPoint("LEFT", 6, 0); ic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        ic:SetTexCoord(0.1, 0.9, 0.1, 0.9); curBtn.icon = ic
        
        local nx = curBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nx:SetPoint("LEFT", ic, "RIGHT", 8, 0); nx:SetJustifyH("LEFT"); curBtn.nameText = nx
        
        curBtn.delBtn = CreateFrame("Button", nil, curBtn)
        loadoutButtons[1] = curBtn
    end
    
    curBtn:SetPoint("TOPLEFT", 2, -yOff)
    curBtn:SetBackdropColor(0.04, 0.08, 0.04, 0.8)
    curBtn:SetBackdropBorderColor(0.2, 0.6, 0.2, 1)
    curBtn.nameText:SetText("|cff88ff88Current Equipped|r")
    if activeLookId == "CURRENT" then curBtn:SetBackdropBorderColor(0.4, 1.0, 0.4, 1); curBtn:SetBackdropColor(0.06, 0.15, 0.06, 0.8) end
    curBtn.delBtn:Hide()
    curBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_08")
    
    curBtn:SetScript("OnClick", function(self)
        activeLookId = "CURRENT"
        BuildListFrames()
        btnUpdate:Disable(); btnApplyLoadout:Disable()
        local cur = CaptureCurrentLoadout(); cur.isCurrent = true
        UpdateLoadoutPreview(cur)
        PlaySound("gsTitleOptionOK")
    end)
    curBtn:Show(); curBtn.layoutIdx = 0
    yOff = yOff + ROW_H + 2
    
    local keys = {}
    for i, _ in ipairs(saved) do table.insert(keys, i) end
    
    for i, accIdx in ipairs(keys) do
        local loadout = saved[accIdx]
        local btnIdx = i + 1
        local btn = loadoutButtons[btnIdx]
        if not btn then
            btn = CreateFrame("Button", nil, listContent)
            btn:SetSize(listContent:GetWidth() - 4, ROW_H)
            btn:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
            btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square"); btn:GetHighlightTexture():SetAlpha(0.1)
            
            local ic = btn:CreateTexture(nil, "OVERLAY")
            ic:SetSize(22, 22); ic:SetPoint("LEFT", 6, 0)
            ic:SetTexCoord(0.1, 0.9, 0.1, 0.9); btn.icon = ic
            
            local nx = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nx:SetPoint("LEFT", ic, "RIGHT", 8, 0); nx:SetPoint("RIGHT", -24, 0)
            nx:SetJustifyH("LEFT"); btn.nameText = nx
            
            local del = CreateFrame("Button", nil, btn)
            del:SetSize(20, 20); del:SetPoint("RIGHT", -4, 0)
            local delTex = del:CreateTexture(nil, "OVERLAY"); delTex:SetAllPoints(); delTex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            del:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
            del:Hide(); btn.delBtn = del
            
            btn:SetScript("OnEnter", function() del:Show() end)
            btn:SetScript("OnLeave", function(self) if not del:IsMouseOver() then del:Hide() end end)
            del:SetScript("OnEnter", function() delTex:SetVertexColor(1, 0.2, 0.2) end)
            del:SetScript("OnLeave", function() delTex:SetVertexColor(1, 1, 1); if not btn:IsMouseOver() then del:Hide() end end)
            
            loadoutButtons[btnIdx] = btn
        end
        
        btn:SetPoint("TOPLEFT", 2, -yOff)
        
        if activeLookId == accIdx then
            btn:SetBackdropColor(0.12, 0.1, 0.06, 0.9)
            btn:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        else
            btn:SetBackdropColor(0.04, 0.04, 0.04, 0.9)
            btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        end
        
        btn.nameText:SetText("|cffffd700"..loadout.name.."|r")
        
        -- Try to find chest icon (async to handle un-cached items on login)
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        if loadout.items and loadout.items[4] and loadout.items[4] > 0 then
            ns.QueryItem(loadout.items[4], function(queriedId, success)
                if success and queriedId == loadout.items[4] then
                    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(queriedId)
                    if tex then btn.icon:SetTexture(tex) end
                end
            end)
        end
        
        btn:SetScript("OnClick", function(self)
            local t = GetTime()
            if t - (self.lastClick or 0) < 0.3 then
                ApplyLoadout(loadout)
            else
                activeLookId = accIdx
                BuildListFrames()
                btnUpdate:Enable(); btnApplyLoadout:Enable()
                UpdateLoadoutPreview(loadout)
            end
            self.lastClick = t
            PlaySound("gsTitleOptionOK")
        end)
        
        btn.delBtn:SetScript("OnClick", function()
            table.remove(_G["TransmorpherLoadoutsAccount"], accIdx)
            if activeLookId == accIdx then activeLookId = "CURRENT"; btnUpdate:Disable(); btnApplyLoadout:Disable(); UpdateLoadoutPreview(CaptureCurrentLoadout()) end
            if type(activeLookId) == "number" and activeLookId > accIdx then activeLookId = activeLookId - 1 end
            BuildListFrames()
        end)
        
        btn:Show(); btn.layoutIdx = i
        yOff = yOff + ROW_H + 2
    end
    
    listContent:SetHeight(math.max(1, yOff))
    
    -- Ensure update and apply buttons match state
    if type(activeLookId) == "number" then btnUpdate:Enable(); btnApplyLoadout:Enable() else btnUpdate:Disable(); btnApplyLoadout:Disable() end
end

local listInit = CreateFrame("Frame")
listInit:RegisterEvent("ADDON_LOADED")
listInit:SetScript("OnEvent", function(self, event, aName)
    if aName == addon and event == "ADDON_LOADED" then
        if not _G["TransmorpherLoadoutsAccount"] then _G["TransmorpherLoadoutsAccount"] = {} end
        BuildListFrames()
    end
end)

-- Top & Bottom Controls
btnAdd:SetScript("OnClick", function()
    local name = newBox:GetText()
    if name ~= "" and _G["TransmorpherLoadoutsAccount"] then
        local l = CaptureCurrentLoadout(); l.name = name
        table.insert(_G["TransmorpherLoadoutsAccount"], l)
        newBox:SetText("")
        activeLookId = #_G["TransmorpherLoadoutsAccount"]
        BuildListFrames()
        UpdateLoadoutPreview(l)
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Loadout '"..name.."' saved!")
        PlaySound("gsTitleOptionOK")
    end
end)
newBox:SetScript("OnEnterPressed", function() btnAdd:GetScript("OnClick")(); newBox:ClearFocus() end)

btnUpdate:SetScript("OnClick", function()
    if type(activeLookId) == "number" and _G["TransmorpherLoadoutsAccount"] then
        local saved = _G["TransmorpherLoadoutsAccount"][activeLookId]
        if saved then
            local l = CaptureCurrentLoadout(); l.name = saved.name
            _G["TransmorpherLoadoutsAccount"][activeLookId] = l
            UpdateLoadoutPreview(l)
            BuildListFrames()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Loadout updated!")
            PlaySound("gsTitleOptionOK")
        end
    end
end)

btnApplyLoadout:SetScript("OnClick", function()
    if type(activeLookId) == "number" and _G["TransmorpherLoadoutsAccount"] then
        local saved = _G["TransmorpherLoadoutsAccount"][activeLookId]
        if saved then ApplyLoadout(saved) end
    end
end)

appearancesTab:SetScript("OnShow", function()
    if activeLookId == "CURRENT" then
        local l = CaptureCurrentLoadout(); l.isCurrent = true
        UpdateLoadoutPreview(l)
    end
end)
