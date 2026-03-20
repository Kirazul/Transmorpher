local addon, ns = ...

-- ============================================================
-- PREVIEW TAB — Items/Sets/Forms sub-tabs, item grid, enchant grid
-- ============================================================

local mainFrame = ns.mainFrame
local _, classFileName = UnitClass("player")
local _, raceFileName = UnitRace("player")
local sex = UnitSex("player")
local previewSetupVersion = "classic"

-- Sub-tabs Containers
local itemsSubTab = CreateFrame("Frame", "$parentItemsSubTab", mainFrame.tabs.preview)
itemsSubTab:SetPoint("TOPLEFT", 0, -50); itemsSubTab:SetPoint("BOTTOMRIGHT")
mainFrame.tabs.preview.itemsSubTab = itemsSubTab

local setsSubTab = CreateFrame("Frame", "$parentSetsSubTab", mainFrame.tabs.preview)
setsSubTab:SetPoint("TOPLEFT", 0, -50); setsSubTab:SetPoint("BOTTOMRIGHT"); setsSubTab:Hide()
mainFrame.tabs.preview.setsSubTab = setsSubTab

local formsSubTab = CreateFrame("Frame", "$parentFormsSubTab", mainFrame.tabs.preview)
formsSubTab:SetPoint("TOPLEFT", 0, -50); formsSubTab:SetPoint("BOTTOMRIGHT"); formsSubTab:Hide()
mainFrame.tabs.preview.formsSubTab = formsSubTab

local spellsSubTab = CreateFrame("Frame", "$parentSpellsSubTab", mainFrame.tabs.preview)
spellsSubTab:SetPoint("TOPLEFT", 0, -50); spellsSubTab:SetPoint("BOTTOMRIGHT"); spellsSubTab:Hide()
mainFrame.tabs.preview.spellsSubTab = spellsSubTab

-- Sub-tab Buttons
local subTabBar = CreateFrame("Frame", nil, mainFrame.tabs.preview)
subTabBar:SetSize(360, 30); subTabBar:SetPoint("TOPLEFT", 0, -20)

local function CreateSubTabButton(parent, id, text)
    local btn = CreateFrame("Button", nil, parent); btn:SetID(id); btn:SetSize(90, 30)
    local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(1,1,1,0); btn.bg = bg
    local line = btn:CreateTexture(nil, "OVERLAY"); line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", 15, 0); line:SetPoint("BOTTOMRIGHT", -15, 0)
    line:SetTexture(1, 0.82, 0); line:Hide(); btn.line = line
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fs:SetPoint("CENTER"); fs:SetText(text); fs:SetTextColor(0.5,0.5,0.5); btn.fs = fs
    btn.SetActive = function(self, active) self.isActive = active
        if active then self.line:Show(); self.fs:SetTextColor(1,1,1); self.bg:SetTexture(1,1,1,0.05)
        else self.line:Hide(); self.fs:SetTextColor(0.5,0.5,0.5); self.bg:SetTexture(0,0,0,0) end
    end
    btn:SetScript("OnEnter", function(self) if not self.isActive then self.fs:SetTextColor(0.9,0.9,0.9); self.bg:SetTexture(1,1,1,0.03) end end)
    btn:SetScript("OnLeave", function(self) if not self.isActive then self.fs:SetTextColor(0.5,0.5,0.5); self.bg:SetTexture(0,0,0,0) end end)
    return btn
end

local btnItems = CreateSubTabButton(subTabBar, 1, "Items"); btnItems:SetPoint("LEFT", 0, 0)
local btnSets = CreateSubTabButton(subTabBar, 2, "Sets"); btnSets:SetPoint("LEFT", btnItems, "RIGHT", 0, 0)
local btnForms = CreateSubTabButton(subTabBar, 3, "Forms"); btnForms:SetPoint("LEFT", btnSets, "RIGHT", 0, 0)
local btnSpells = CreateSubTabButton(subTabBar, 4, "Spells"); btnSpells:SetPoint("LEFT", btnForms, "RIGHT", 0, 0)

local function ShowPreviewSubTab(id)
    local showItems = id == 1
    local showSets = id == 2
    local showForms = id == 3
    local showSpells = id == 4

    if showItems then itemsSubTab:Show() else itemsSubTab:Hide() end
    if showSets then setsSubTab:Show() else setsSubTab:Hide() end
    if showForms then formsSubTab:Show() else formsSubTab:Hide() end
    if showSpells then spellsSubTab:Show() else spellsSubTab:Hide() end

    btnItems:SetActive(showItems)
    btnSets:SetActive(showSets)
    btnForms:SetActive(showForms)
    btnSpells:SetActive(showSpells)

    if showSets and not setsSubTab.initialized then
        if ns.InitSetsTab then ns.InitSetsTab(setsSubTab); setsSubTab.initialized = true end
    end
    if showForms and not formsSubTab.initialized then
        if ns.InitFormsTab then ns.InitFormsTab(formsSubTab); formsSubTab.initialized = true end
    end
    if showSpells and not spellsSubTab.initialized then
        if ns.InitSpellsTab then ns.InitSpellsTab(spellsSubTab); spellsSubTab.initialized = true end
    end

    PlaySound("gsTitleOptionOK")
end
btnItems:SetScript("OnClick", function() ShowPreviewSubTab(1) end)
btnSets:SetScript("OnClick", function() ShowPreviewSubTab(2) end)
btnForms:SetScript("OnClick", function() ShowPreviewSubTab(3) end)
btnSpells:SetScript("OnClick", function() ShowPreviewSubTab(4) end)
mainFrame.tabs.preview.ShowSubTab = ShowPreviewSubTab
mainFrame.tabs.preview:SetScript("OnShow", function(self)
    if not self.tabInitialized then
        ShowPreviewSubTab(1)
        self.tabInitialized = true
    end
end)

-- NOTE: ns.InitFormsTab is defined in UI\Tabs\FormsTab.lua (loaded later in TOC)

-- ============================================================
-- ITEMS SUB-TAB — Preview list, slider, search, dropdown
-- ============================================================
mainFrame.tabs.preview.list = ns.CreatePreviewList(itemsSubTab)
mainFrame.tabs.preview.slider = CreateFrame("Slider", "$parentSlider", itemsSubTab, "UIPanelScrollBarTemplateLightBorder")

do
    local previewTab = itemsSubTab
    local list = mainFrame.tabs.preview.list
    local slider = mainFrame.tabs.preview.slider

    -- Dropdown container
    local dropContainer = CreateFrame("Frame", nil, previewTab)
    previewTab.dropContainer = dropContainer
    dropContainer:SetSize(170, 26); dropContainer:SetPoint("TOPRIGHT", -6, -2)
    dropContainer:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Buttons\\WHITE8X8", tile=false, tileSize=0, edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
    dropContainer:SetBackdropColor(0.08, 0.08, 0.08, 0.95); dropContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local dropBtn = CreateFrame("Button", "$parentSubDropBtn", dropContainer)
    previewTab.dropBtn = dropBtn; dropBtn:SetAllPoints(); dropBtn:EnableMouse(true)
    local dropText = dropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewTab.dropText = dropText; dropText:SetPoint("LEFT", 8, 0); dropText:SetPoint("RIGHT", -20, 0); dropText:SetJustifyH("LEFT"); dropText:SetTextColor(0.95, 0.88, 0.65)
    local dropArrow = dropBtn:CreateTexture(nil, "OVERLAY")
    previewTab.dropArrow = dropArrow; dropArrow:SetSize(14, 14); dropArrow:SetPoint("RIGHT", -4, 0)
    dropArrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow"); dropArrow:SetVertexColor(0.80, 0.65, 0.22)

    dropBtn:SetScript("OnEnter", function() dropContainer:SetBackdropBorderColor(0.80, 0.65, 0.22, 1) end)
    dropBtn:SetScript("OnLeave", function() dropContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8) end)

    local dropList = CreateFrame("Frame", "$parentSubDropList", previewTab)
    previewTab.dropList = dropList
    dropList:SetPoint("TOPLEFT", dropContainer, "BOTTOMLEFT", 0, 2); dropList:SetPoint("TOPRIGHT", dropContainer, "BOTTOMRIGHT", 0, 2)
    dropList:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Buttons\\WHITE8X8", tile=false, tileSize=0, edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
    dropList:SetBackdropColor(0.08, 0.08, 0.08, 0.97); dropList:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    dropList:SetFrameStrata("DIALOG"); dropList:Hide()
    local DROP_ROW_H = 20; previewTab.DROP_ROW_H = DROP_ROW_H
    local dropListButtons = {}; previewTab.dropListButtons = dropListButtons

    -- Search bar
    local searchContainer = CreateFrame("Frame", nil, previewTab)
    searchContainer:SetPoint("TOPLEFT", 6, -2); searchContainer:SetPoint("RIGHT", dropContainer, "LEFT", -6, 0); searchContainer:SetHeight(26)
    searchContainer:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Buttons\\WHITE8X8", tile=false, tileSize=0, edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
    searchContainer:SetBackdropColor(0.08, 0.08, 0.08, 0.95); searchContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local searchIcon = searchContainer:CreateTexture(nil, "OVERLAY"); searchIcon:SetSize(14,14); searchIcon:SetPoint("LEFT", 6, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon"); searchIcon:SetVertexColor(0.80, 0.65, 0.22)

    local searchBox = CreateFrame("EditBox", "$parentPreviewSearch", searchContainer)
    searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0); searchBox:SetPoint("RIGHT", -24, 0); searchBox:SetHeight(18)
    searchBox:SetAutoFocus(false); searchBox:SetMaxLetters(60)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11); searchBox:SetTextColor(0.95, 0.88, 0.65)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", 2, 0); searchPlaceholder:SetText("Search by name or item ID...")
    searchBox:SetScript("OnEditFocusGained", function() searchPlaceholder:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then searchPlaceholder:Show() end end)

    local searchClear = CreateFrame("Button", nil, searchContainer)
    searchClear:SetSize(14,14); searchClear:SetPoint("RIGHT", -4, 0)
    searchClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon"); searchClear:SetAlpha(0.5); searchClear:Hide()
    searchClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    searchClear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)

    previewTab.searchQuery = ""
    previewTab.searchResults = nil

    list:SetPoint("TOPLEFT", 0, -30); list:SetSize(601, 367)
    local label = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", list, "BOTTOM", 0, 0); label:SetJustifyH("CENTER"); label:SetHeight(10); label:SetTextColor(0.85, 0.70, 0.40)

    slider:SetPoint("TOPRIGHT", -6, -21); slider:SetPoint("BOTTOMRIGHT", -6, 21)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() - delta) end)
    slider:SetScript("OnMinMaxChanged", function(self, min, max) label:SetText(("Page: %s/%s"):format(self:GetValue(), max)) end)
    slider.buttons = {}
    slider.buttons.up = _G[slider:GetName().."ScrollUpButton"]
    slider.buttons.down = _G[slider:GetName().."ScrollDownButton"]
    slider.buttons.up:SetScript("OnClick", function() slider:SetValue(slider:GetValue()-1); PlaySound("gsTitleOptionOK") end)
    slider.buttons.down:SetScript("OnClick", function() slider:SetValue(slider:GetValue()+1); PlaySound("gsTitleOptionOK") end)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta) slider:SetValue(slider:GetValue()-delta) end)
    slider:SetScript("OnValueChanged", function(self, value) local _, max = self:GetMinMaxValues(); label:SetText(("Page: %s/%s"):format(value, max)) end)
    slider:SetMinMaxValues(0, 0); slider:SetValueStep(1)

    -- State
    local slotSubclassPage = {}
    for slot, _ in pairs(mainFrame.slots) do slotSubclassPage[slot] = {} end
    local defaultSlot = ns.slotOrder and ns.slotOrder[4] or "Chest"
    local defaultArmorSubclass = ns.defaultArmorSubclass or {}
    previewTab.currSlot = defaultSlot
    previewTab.currSubclass = defaultArmorSubclass[classFileName] or "Mail"
    local currSlot = previewTab.currSlot
    local currSubclass = previewTab.currSubclass
    local records
    local enchantRecords = {}
    local enchantPage = 1
    local RefreshEnchantList

    local arrayHasValue = ns.ArrayHasValue

    previewTab.RefreshEnchantList = function() if RefreshEnchantList then RefreshEnchantList() end end

    -- Core update
    previewTab.Update = function(self, slot, subclass)
        slotSubclassPage[previewTab.currSlot][previewTab.currSubclass] = slider:GetValue() > 0 and slider:GetValue() or 1
        previewTab.currSlot = slot; previewTab.currSubclass = subclass
        currSlot = slot; currSubclass = subclass
        records = ns.GetSubclassRecords(slot, subclass) or {}

        local query = previewTab.searchQuery or ""
        local filteredRecords, filteredItemIds = {}, {}
        local selectedItemId

        if query ~= "" then
            local lQ = query:lower(); local nQ = tonumber(query)
            for i = 1, #records do
                local ids, names = records[i][1], records[i][2]
                local match = false
                for j = 1, #ids do
                    if nQ and ids[j] == nQ then match = true; break end
                    if names[j] and names[j]:lower():find(lQ, 1, true) then match = true; break end
                end
                if match then table.insert(filteredRecords, records[i]); table.insert(filteredItemIds, ids[1])
                    if not selectedItemId and mainFrame.slots[slot].itemId and arrayHasValue(ids, mainFrame.slots[slot].itemId) then selectedItemId = ids[1] end
                end
            end
            records = filteredRecords
        else
            for i = 1, #records do
                local ids = records[i][1]; table.insert(filteredItemIds, ids[1])
                if not selectedItemId and mainFrame.slots[slot].itemId and arrayHasValue(ids, mainFrame.slots[slot].itemId) then selectedItemId = ids[1] end
            end
        end

        list:SetItems(filteredItemIds)
        if selectedItemId then list:SelectByItemId(selectedItemId) end

        if #filteredItemIds > 0 then
            local setup = ns.GetPreviewSetup(previewSetupVersion, raceFileName, sex, slot, subclass)
            list:SetupModel(setup.width, setup.height, setup.x, setup.y, setup.z, setup.facing, setup.sequence)
            list:TryOn(nil)
            local page = query == "" and (slotSubclassPage[slot][subclass] or 1) or 1
            local pageCount = math.max(1, list:GetPageCount())
            if page > pageCount then page = pageCount end
            slider:SetMinMaxValues(1, pageCount)
            if slider:GetValue() ~= page then slider:SetValue(page) else list:SetPage(page); list:Update() end
        else
            slider:SetMinMaxValues(1, 1); slider:SetValue(1)
        end
    end

    -- Search debounce
    local searchTimer = CreateFrame("Frame"); searchTimer:Hide(); searchTimer.elapsed = 0

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText(); previewTab.searchQuery = text
        if text ~= "" then searchClear:Show(); searchPlaceholder:Hide() else searchClear:Hide() end
        searchTimer.elapsed = 0; searchTimer:Show()
    end)

    searchClear:SetScript("OnClick", function()
        searchBox:SetText(""); searchBox:ClearFocus(); searchPlaceholder:Show(); searchClear:Hide(); previewTab.searchQuery = ""
        if previewTab.enchantMode then enchantPage = 1; if RefreshEnchantList then RefreshEnchantList() end end
    end)

    searchBox:SetScript("OnEnterPressed", function(self)
        searchTimer:Hide()
        if previewTab.enchantMode then enchantPage = 1; if RefreshEnchantList then RefreshEnchantList() end else previewTab:Update(currSlot, currSubclass) end
        self:ClearFocus()
    end)

    -- Item slot click handling
    local selectedInRecord = {}
    local enteredButton
    local tabDummy = CreateFrame("Button", addon.."PreviewListTabDummy", previewTab)

    list.onEnter = function(self)
        if previewTab.enchantMode then
            local idx = self:GetParent().itemIndex
            local entry = enchantRecords[idx]
            if not entry then return end
            GameTooltip:Hide(); GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT"); GameTooltip:ClearLines()
            GameTooltip:AddLine("|cffF5C842"..entry.name.."|r")
            GameTooltip:AddLine("Enchant ID: "..entry.id, 0.7, 0.7, 0.7)
            GameTooltip:Show()
            return
        end
        local recordIndex = self:GetParent().itemIndex
        if not records or not records[recordIndex] then return end
        local ids, names = records[recordIndex][1], records[recordIndex][2]
        GameTooltip:Hide(); GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT"); GameTooltip:ClearLines()
        GameTooltip:AddLine("This appearance is provided by:", 1, 1, 1); GameTooltip:AddLine(" ")
        local selIdx = selectedInRecord[ids[1]] or 1
        for i, id in ipairs(ids) do
            GameTooltip:AddLine((i == selIdx and "> " or "- ")..names[i]..(id == (mainFrame.selectedSlot and mainFrame.selectedSlot.itemId) and " *" or ""))
        end
        GameTooltip:Show()
        SetOverrideBindingClick(tabDummy, true, "TAB", tabDummy:GetName(), "RightButton"); enteredButton = self
    end
    list.onLeave = function() ClearOverrideBindings(tabDummy); GameTooltip:ClearLines(); GameTooltip:Hide(); enteredButton = nil end

    tabDummy:SetScript("OnClick", function()
        if previewTab.enchantMode then return end
        if enteredButton then
            local ri = enteredButton:GetParent().itemIndex; local ids = records[ri][1]
            if #ids > 1 then
                if not selectedInRecord[ids[1]] then selectedInRecord[ids[1]] = 2
                else selectedInRecord[ids[1]] = selectedInRecord[ids[1]] < #ids and selectedInRecord[ids[1]] + 1 or 1 end
            end
            list.onEnter(enteredButton)
        end
    end)

    list.onItemClick = function(self, button)
        if previewTab.enchantMode then
            local idx = self:GetParent().itemIndex
            local entry = enchantRecords[idx]
            if not entry then return end
            local enchSlot = mainFrame.selectedEnchantSlot
            if not enchSlot then return end
            enchSlot:SetEnchant(entry.id, entry.name)
            mainFrame.tabs.preview.list:SelectByItemId(entry.id)
            PlaySound("gsTitleOptionOK")
            list.onEnter(self)
            return
        end
        local ri = self:GetParent().itemIndex
        if not records or not records[ri] then return end
        local ids, names = records[ri][1], records[ri][2]
        local selIdx = selectedInRecord[ids[1]] or 1; local itemId = ids[selIdx]
        if IsShiftKeyDown() then
            local color = names[selIdx]:sub(1,10); local name = names[selIdx]:sub(11,-3)
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: "..color.."\\124Hitem:"..itemId..":::::::|h["..name.."]\\124h\\124r".." ("..itemId..")")
        elseif IsControlKeyDown() then
            ns.ShowWowheadURLDialog(itemId)
        else
            if mainFrame.selectedSlot then mainFrame.selectedSlot:SetItem(itemId); ns.HideMorphGlow(mainFrame.selectedSlot) end
        end
        list.onEnter(self)
    end

    -- Slider hooks for item paging
    slider:HookScript("OnValueChanged", function(self, value)
        if previewTab.enchantMode then return end
        list:SetPage(value); if #list.itemIds > 0 then list:Update() end
    end)

    -- ============================================================
    -- ENCHANT BROWSING MODE
    -- ============================================================
    previewTab.enchantMode = false; previewTab.enchantSlotName = nil
    previewTab.enchantRenderToken = 0

    local function GetWeaponCameraSetup()
        local wantsOffhand = previewTab.enchantSlotName == "Enchant OH"
        local offhandId = GetInventoryItemID("player", 17) or 0
        local offhandEquipSlot = nil
        if offhandId > 0 then
            local _, _, _, _, _, _, _, _, eq = GetItemInfo(offhandId)
            offhandEquipSlot = eq
        end
        local offhandUsable = offhandId > 0 and (
            offhandEquipSlot == "INVTYPE_WEAPONOFFHAND" or
            offhandEquipSlot == "INVTYPE_WEAPON" or
            offhandEquipSlot == "INVTYPE_SHIELD" or
            offhandEquipSlot == "INVTYPE_HOLDABLE"
        )
        local wSlot = (wantsOffhand and offhandUsable) and "Off-hand" or "Main Hand"
        local invSlotId = (wSlot == "Off-hand") and 17 or 16
        local equippedWeaponId = GetInventoryItemID("player", invSlotId)
            or (mainFrame.slots[wSlot] and mainFrame.slots[wSlot].itemId)
            or 0
        if equippedWeaponId <= 0 then
            local fallbackSubclasses
            if wSlot == "Off-hand" then
                fallbackSubclasses = {"OH Sword", "OH Axe", "OH Mace", "OH Dagger", "OH Fist", "Shield", "Held in Off-hand"}
            else
                fallbackSubclasses = {"1H Sword", "1H Axe", "1H Mace", "1H Dagger", "1H Fist", "MH Sword", "MH Axe", "MH Mace", "MH Dagger", "MH Fist"}
            end
            for _, fallbackSubclass in ipairs(fallbackSubclasses) do
                local rec = ns.GetSubclassRecords and ns.GetSubclassRecords(wSlot, fallbackSubclass)
                if rec and rec[1] and rec[1][1] and rec[1][1][1] then
                    equippedWeaponId = rec[1][1][1]
                    break
                end
            end
        end
        if not equippedWeaponId or equippedWeaponId <= 0 then
            equippedWeaponId = 25
        end
        local _, _, _, _, _, _, subclass, _, equipSlot = GetItemInfo(equippedWeaponId)
        if not subclass or subclass == "" then subclass = "Sword" end
        local lookupSubclass = subclass
        if equipSlot == "INVTYPE_WEAPONOFFHAND" then
            lookupSubclass = "OH " .. subclass
        elseif equipSlot == "INVTYPE_WEAPONMAINHAND" then
            lookupSubclass = "MH " .. subclass
        elseif equipSlot == "INVTYPE_WEAPON" then
            lookupSubclass = "1H " .. subclass
        elseif equipSlot == "INVTYPE_2HWEAPON" then
            lookupSubclass = "2H " .. subclass
        elseif equipSlot == "INVTYPE_HOLDABLE" then
            lookupSubclass = "Held in Off-hand"
        elseif wSlot == "Off-hand" then
            lookupSubclass = "OH " .. subclass
        else
            lookupSubclass = "MH " .. subclass
        end
        local setup = ns.GetPreviewSetup("classic", raceFileName, sex, wSlot, lookupSubclass)
        return setup, equippedWeaponId
    end

    RefreshEnchantList = function()
        if not previewTab.enchantMode then return end
        previewTab.enchantRenderToken = previewTab.enchantRenderToken + 1
        local renderToken = previewTab.enchantRenderToken
        local query = (previewTab.searchQuery or ""):lower()
        wipe(enchantRecords)
        for _, entry in ipairs(ns.enchantSorted) do
            if query == "" or entry.nameLower:find(query, 1, true) or tostring(entry.id):find(query, 1, true) then
                table.insert(enchantRecords, entry)
            end
        end
        local bodyCamera, weaponId = GetWeaponCameraSetup()
        local camX, camY, camZ, camFacing
        if bodyCamera then
            camX = bodyCamera.x
            camY = bodyCamera.y
            camZ = bodyCamera.z
            camFacing = bodyCamera.facing or 0
        else
            camX, camY, camZ, camFacing = 4, 0, 0, 0
        end
        if previewTab.enchantSlotName == "Enchant OH" then
            camY = camY + 0.35
        end

        local function RenderWithWeapon(resolvedWeaponId)
            if not previewTab.enchantMode or renderToken ~= previewTab.enchantRenderToken then return end
            list:SetCustomRenderer(function(dr, entry)
                dr:OnUpdateModel(nil)
                dr:TryOn(resolvedWeaponId)
                dr:TryOn("item:"..resolvedWeaponId..":"..entry.id..":0:0:0:0:0:0")
                dr:SetSequence(52)
            end)
            list:SetCustomEntries(enchantRecords)
            list:SetupModel(116, 176, camX, camY, camZ, camFacing, (bodyCamera and bodyCamera.sequence) or 0)
            list:TryOn(nil)

            local pageCount = math.max(1, list:GetPageCount())
            if enchantPage > pageCount then enchantPage = pageCount end
            if enchantPage < 1 then enchantPage = 1 end
            slider:SetMinMaxValues(1, pageCount)
            if slider:GetValue() ~= enchantPage then slider:SetValue(enchantPage) else list:SetPage(enchantPage); list:Update() end

            local curId = mainFrame.selectedEnchantSlot and mainFrame.selectedEnchantSlot.enchantId
            if curId then list:SelectByItemId(curId) end
            label:SetText(("Page: %d/%d  (%d enchants)"):format(enchantPage, pageCount, #enchantRecords))
            if C_Timer and C_Timer.After then
                C_Timer.After(0.08, function()
                    if not previewTab.enchantMode or renderToken ~= previewTab.enchantRenderToken then return end
                    list:Update()
                    if curId then list:SelectByItemId(curId) end
                end)
            end
        end

        ns.QueryItem(weaponId, function(queriedWeaponId, success)
            if success then
                RenderWithWeapon(queriedWeaponId)
            else
                RenderWithWeapon(weaponId)
            end
        end)
    end

    previewTab.UpdateEnchantMode = function(self, enchantSlotName)
        self.enchantMode = true; self.enchantSlotName = enchantSlotName
        list:Show(); dropContainer:Hide(); slider:Show()
        searchPlaceholder:SetText("Search enchants..."); searchBox:SetText(""); self.searchQuery = ""; searchClear:Hide(); searchPlaceholder:Show()
        enchantPage = 1
        if self:IsShown() then RefreshEnchantList() end
    end
    previewTab.ExitEnchantMode = function(self)
        if not self.enchantMode then return end; self.enchantMode = false; self.enchantSlotName = nil
        list:SetCustomEntries(nil)
        list:SetCustomRenderer(nil)
        list:Show(); slider:Show(); dropContainer:Show()
        searchPlaceholder:SetText("Search by name or item ID..."); searchBox:SetText(""); self.searchQuery = ""; searchClear:Hide(); searchPlaceholder:Show()
    end

    -- Search timer
    searchTimer:SetScript("OnUpdate", function(self, dt) self.elapsed = self.elapsed + dt
        if self.elapsed >= 0.3 then self:Hide()
            if previewTab.enchantMode then enchantPage = 1; RefreshEnchantList() else previewTab:Update(currSlot, currSubclass) end
        end
    end)

    itemsSubTab:SetScript("OnShow", function(self)
        if self.enchantMode then 
            if self.RefreshEnchantList then self.RefreshEnchantList() end
        else 
            if self.Update then self:Update(self.currSlot, self.currSubclass) end
        end
    end)

    -- Enchant slider hook
    local enchSliderUpdating = false
    slider:HookScript("OnValueChanged", function(self, value)
        if previewTab.enchantMode and not enchSliderUpdating then
            local np = math.floor(value + 0.5)
            if np ~= enchantPage then
                enchantPage = np
                enchSliderUpdating = true
                list:SetPage(np)
                list:Update()
                local curId = mainFrame.selectedEnchantSlot and mainFrame.selectedEnchantSlot.enchantId
                if curId then list:SelectByItemId(curId) end
                label:SetText(("Page: %d/%d  (%d enchants)"):format(enchantPage, math.max(1, list:GetPageCount()), #enchantRecords))
                enchSliderUpdating = false
            end
        end
    end)
end

-- ============================================================
-- SUBCLASS DROPDOWN (Custom Golden)
-- ============================================================
mainFrame.tabs.preview.subclassMenu = {}
do
    local previewTab = mainFrame.tabs.preview.itemsSubTab
    local menu = mainFrame.tabs.preview.subclassMenu
    local dropContainer = previewTab.dropContainer
    local dropBtn = previewTab.dropBtn
    local dropText = previewTab.dropText
    local dropArrow = previewTab.dropArrow
    local dropList = previewTab.dropList
    local dropListButtons = previewTab.dropListButtons
    local DROP_ROW_H = previewTab.DROP_ROW_H

    local slotSubclasses = ns.slotSubclasses or {}
    local defaultArmorSubclass = ns.defaultArmorSubclass or {}
    local armorSlots = ns.armorSlots or {}
    local miscellaneousSlots = ns.miscSlots or {}
    local backSlot = ns.backSlot or "Back"
    local mainHandSlot = ns.mainHandSlot or "Main Hand"
    local offHandSlot = ns.offHandSlot or "Off-hand"
    local rangedSlot = ns.rangedSlot or "Ranged"

    local slotSelectedSubclass = {}
    for _, slot in ipairs(armorSlots) do slotSelectedSubclass[slot] = defaultArmorSubclass[classFileName] or "Mail" end
    for _, slot in ipairs(miscellaneousSlots) do slotSelectedSubclass[slot] = "Miscellaneous" end
    if slotSubclasses[backSlot] then slotSelectedSubclass[backSlot] = slotSubclasses[backSlot][1] end
    if slotSubclasses[mainHandSlot] then slotSelectedSubclass[mainHandSlot] = slotSubclasses[mainHandSlot][1] end
    if slotSubclasses[offHandSlot] then slotSelectedSubclass[offHandSlot] = slotSubclasses[offHandSlot][1] end
    if slotSubclasses[rangedSlot] then slotSelectedSubclass[rangedSlot] = slotSubclasses[rangedSlot][1] end

    menu.currentSlot = nil

    local function BuildDropList(slot)
        for _, b in ipairs(dropListButtons) do b:Hide() end
        local subclasses = slotSubclasses[slot]; if not subclasses then return end
        local totalH = 0
        for i, subclass in ipairs(subclasses) do
            local btn = dropListButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, dropList); btn:SetHeight(DROP_ROW_H)
                btn:SetPoint("TOPLEFT", 4, -4 - (i-1)*DROP_ROW_H); btn:SetPoint("TOPRIGHT", -4, -4 - (i-1)*DROP_ROW_H)
                btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD"); btn:GetHighlightTexture():SetVertexColor(0.80,0.65,0.22,0.3)
                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); btn.text:SetPoint("LEFT", 6, 0); btn.text:SetJustifyH("LEFT")
                btn.check = btn:CreateTexture(nil, "OVERLAY"); btn.check:SetSize(12,12); btn.check:SetPoint("RIGHT", -4, 0)
                btn.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); btn.check:SetVertexColor(0.95,0.80,0.30)
                dropListButtons[i] = btn
            end
            local isSel = (subclass == slotSelectedSubclass[slot])
            btn.text:SetText(subclass)
            if isSel then btn.text:SetTextColor(1.0,0.84,0.40); btn.check:Show() else btn.text:SetTextColor(0.85,0.78,0.55); btn.check:Hide() end
            btn:SetScript("OnClick", function()
                slotSelectedSubclass[slot] = subclass; dropText:SetText(subclass); dropList:Hide()
                previewTab:Update(slot, subclass)
            end)
            btn:Show(); totalH = totalH + DROP_ROW_H
        end
        dropList:SetHeight(totalH + 8)
    end

    dropBtn:SetScript("OnClick", function()
        if dropList:IsShown() then dropList:Hide() else if menu.currentSlot then BuildDropList(menu.currentSlot) end; dropList:Show() end
    end)

    dropList:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end; if dropBtn:IsMouseOver() or self:IsMouseOver() then self.leaveTimer = nil; return end
        for _, b in ipairs(dropListButtons) do if b:IsShown() and b:IsMouseOver() then self.leaveTimer = nil; return end end
        if not self.leaveTimer then self.leaveTimer = 0 end; self.leaveTimer = self.leaveTimer + 0.02
        if self.leaveTimer > 0.35 then self:Hide(); self.leaveTimer = nil end
    end)
    dropList:HookScript("OnShow", function(self) self.leaveTimer = nil end)
    dropBtn:HookScript("OnEnter", function() dropList.leaveTimer = nil end)

    menu.Update = function(self, slot)
        self.currentSlot = slot; local subclass = slotSelectedSubclass[slot]; dropText:SetText(subclass); dropList:Hide()
        if slotSubclasses[slot] and #slotSubclasses[slot] > 1 then
            dropArrow:SetVertexColor(0.80,0.65,0.22); dropText:SetTextColor(0.95,0.88,0.65); dropBtn:Enable()
        else
            dropArrow:SetVertexColor(0.40,0.35,0.20); dropText:SetTextColor(0.50,0.45,0.30); dropBtn:Disable()
        end
        previewTab:Update(slot, subclass)
    end
end
