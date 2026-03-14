local addon, ns = ...

function ns.InitSetsTab(parent)
    local frame = parent
    local BuildList
    local SelectSet

    local classDisplayNames = {
        ALL = "All",
        WARRIOR = "Warrior",
        PALADIN = "Paladin",
        HUNTER = "Hunter",
        ROGUE = "Rogue",
        PRIEST = "Priest",
        DEATHKNIGHT = "Death Knight",
        SHAMAN = "Shaman",
        MAGE = "Mage",
        WARLOCK = "Warlock",
        DRUID = "Druid",
    }

    local classes = {
        "ALL", "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
        "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
    }

    local listContainer = CreateFrame("Frame", nil, frame)
    listContainer:SetPoint("TOPLEFT", 4, -4)
    listContainer:SetPoint("BOTTOMLEFT", 4, 4)
    listContainer:SetWidth(200)
    listContainer:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    listContainer:SetBackdropColor(0.06, 0.05, 0.03, 0.7)
    listContainer:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.8)

    local currentFilter = "ALL"
    local searchQuery = ""
    local setsButtons = {}
    local selectedSet

    local filterBtn = CreateFrame("Button", nil, listContainer)
    filterBtn:SetSize(180, 24)
    filterBtn:SetPoint("TOP", 0, -8)

    local filterBtnBg = filterBtn:CreateTexture(nil, "BACKGROUND")
    filterBtnBg:SetAllPoints()
    filterBtnBg:SetTexture(0.1, 0.1, 0.1, 0.82)

    local filterBtnBorder = filterBtn:CreateTexture(nil, "BORDER")
    filterBtnBorder:SetPoint("TOPLEFT", -1, 1)
    filterBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    filterBtnBorder:SetTexture(0.55, 0.45, 0.18, 0.8)

    local filterBtnIcon = filterBtn:CreateTexture(nil, "ARTWORK")
    filterBtnIcon:SetSize(16, 16)
    filterBtnIcon:SetPoint("LEFT", 6, 0)

    local filterBtnText = filterBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterBtnText:SetPoint("LEFT", filterBtnIcon, "RIGHT", 6, 0)
    filterBtnText:SetTextColor(0.95, 0.93, 0.88)

    local filterBtnArrow = filterBtn:CreateTexture(nil, "OVERLAY")
    filterBtnArrow:SetSize(16, 16)
    filterBtnArrow:SetPoint("RIGHT", -4, 0)
    filterBtnArrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

    local filterMenu = CreateFrame("Frame", nil, filterBtn)
    filterMenu:SetPoint("TOPLEFT", filterBtn, "BOTTOMLEFT", 0, 0)
    filterMenu:SetPoint("TOPRIGHT", filterBtn, "BOTTOMRIGHT", 0, 0)
    filterMenu:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    filterMenu:SetBackdropColor(0.06, 0.05, 0.03, 0.99)
    filterMenu:SetBackdropBorderColor(0.60, 0.50, 0.18, 0.9)
    filterMenu:SetFrameStrata("DIALOG")
    filterMenu:Hide()

    local classIconCoords = {
        WARRIOR = {0, 0.25, 0, 0.25},
        MAGE = {0.25, 0.49609375, 0, 0.25},
        ROGUE = {0.49609375, 0.7421875, 0, 0.25},
        DRUID = {0.7421875, 0.98828125, 0, 0.25},
        HUNTER = {0, 0.25, 0.25, 0.5},
        SHAMAN = {0.25, 0.49609375, 0.25, 0.5},
        PRIEST = {0.49609375, 0.7421875, 0.25, 0.5},
        WARLOCK = {0.7421875, 0.98828125, 0.25, 0.5},
        PALADIN = {0, 0.25, 0.5, 0.75},
        DEATHKNIGHT = {0.25, 0.49609375, 0.5, 0.75},
    }

    local function SetClassIcon(texture, cls)
        if cls == "ALL" then
            texture:SetTexture("Interface\\Icons\\INV_Chest_Plate04")
            texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            return
        end
        texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        local coords = classIconCoords[cls]
        if coords then
            texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            texture:SetTexCoord(0, 1, 0, 1)
        end
    end

    local function SelectFilter(cls)
        currentFilter = cls
        filterBtnText:SetText("Class: " .. (classDisplayNames[cls] or cls))
        SetClassIcon(filterBtnIcon, cls)
        filterMenu:Hide()
        BuildList()
    end

    local menuHeight = 0
    for i, cls in ipairs(classes) do
        local btn = CreateFrame("Button", nil, filterMenu)
        btn:SetHeight(20)
        btn:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
        btn:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 20)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 4, 0)
        SetClassIcon(icon, cls)

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetText(classDisplayNames[cls] or cls)
        label:SetTextColor(1, 1, 1)

        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        btn:SetScript("OnClick", function()
            SelectFilter(cls)
        end)

        menuHeight = menuHeight + 20
    end
    filterMenu:SetHeight(menuHeight + 8)

    filterBtn:SetScript("OnClick", function()
        if filterMenu:IsShown() then
            filterMenu:Hide()
        else
            filterMenu:Show()
        end
    end)

    local searchFrame = CreateFrame("Frame", nil, listContainer)
    searchFrame:SetSize(180, 24)
    searchFrame:SetPoint("TOP", filterBtn, "BOTTOM", 0, -8)
    searchFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    searchFrame:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    searchFrame:SetBackdropBorderColor(0.58, 0.48, 0.2, 0.78)

    local searchIcon = searchFrame:CreateTexture(nil, "ARTWORK")
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 7, 0)
    searchIcon:SetVertexColor(0.8, 0.75, 0.62)

    local searchBox = CreateFrame("EditBox", "$parentSetsSearchBox", searchFrame)
    searchBox:SetPoint("TOPLEFT", searchFrame, "TOPLEFT", 24, -3)
    searchBox:SetPoint("BOTTOMRIGHT", searchFrame, "BOTTOMRIGHT", -6, 3)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("ChatFontNormal")
    searchBox:SetTextColor(1, 1, 1)
    searchBox:SetJustifyH("LEFT")
    searchBox:SetTextInsets(0, 0, 0, 0)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", 0, 0)
    searchPlaceholder:SetText("Search Sets...")

    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "" then
            searchPlaceholder:Hide()
        end
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            searchPlaceholder:Show()
        end
    end)
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text == "" then
            searchPlaceholder:Show()
        else
            searchPlaceholder:Hide()
        end
        searchQuery = string.lower(text)
        BuildList()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", listContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)

    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(170, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local model = ns.CreateDressingRoom("$parentModel", frame)
    model:SetPoint("TOPLEFT", listContainer, "TOPRIGHT", 10, 0)
    model:SetPoint("BOTTOMRIGHT", -4, 60)

    model.backgroundTextures = {}
    local bgKeys = "human,nightelf,dwarf,gnome,draenei,orc,scourge,tauren,troll,bloodelf"
    for key in bgKeys:gmatch("%w+") do
        local tex = model:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetTexture("Interface\\AddOns\\Transmorpher\\images\\" .. key)
        tex:SetAlpha(0.48)
        tex:Hide()
        model.backgroundTextures[key] = tex
    end

    local raceToBgKey = {
        Human = "human",
        NightElf = "nightelf",
        Dwarf = "dwarf",
        Gnome = "gnome",
        Draenei = "draenei",
        Orc = "orc",
        Scourge = "scourge",
        Tauren = "tauren",
        Troll = "troll",
        BloodElf = "bloodelf",
    }

    local function ShowModelBackground()
        if not model.backgroundTextures then
            return
        end
        for _, tex in pairs(model.backgroundTextures) do
            tex:Hide()
        end
        local _, raceFileName = UnitRace("player")
        local key = raceToBgKey[raceFileName] or "human"
        local bg = model.backgroundTextures[key]
        if bg then
            bg:Show()
            bg:SetAllPoints(frame)
        end
    end

    model:HookScript("OnShow", ShowModelBackground)
    ShowModelBackground()

    local slotConfig = {
        { slot = "Head", point = "TOPLEFT", x = 4, y = -4 },
        { slot = "Shoulder", point = "TOPLEFT", x = 4, y = -42 },
        { slot = "Back", point = "TOPLEFT", x = 4, y = -80 },
        { slot = "Chest", point = "TOPLEFT", x = 4, y = -118 },
        { slot = "Shirt", point = "TOPLEFT", x = 4, y = -156 },
        { slot = "Tabard", point = "TOPLEFT", x = 4, y = -194 },
        { slot = "Wrist", point = "TOPLEFT", x = 4, y = -232 },
        { slot = "Hands", point = "TOPRIGHT", x = -4, y = -4 },
        { slot = "Waist", point = "TOPRIGHT", x = -4, y = -42 },
        { slot = "Legs", point = "TOPRIGHT", x = -4, y = -80 },
        { slot = "Feet", point = "TOPRIGHT", x = -4, y = -118 },
    }

    local slotTextures = {
        ["Head"] = "Interface\\Paperdoll\\ui-paperdoll-slot-head",
        ["Shoulder"] = "Interface\\Paperdoll\\ui-paperdoll-slot-shoulder",
        ["Back"] = "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
        ["Chest"] = "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
        ["Shirt"] = "Interface\\Paperdoll\\ui-paperdoll-slot-shirt",
        ["Tabard"] = "Interface\\Paperdoll\\ui-paperdoll-slot-tabard",
        ["Wrist"] = "Interface\\Paperdoll\\ui-paperdoll-slot-wrists",
        ["Hands"] = "Interface\\Paperdoll\\ui-paperdoll-slot-hands",
        ["Waist"] = "Interface\\Paperdoll\\ui-paperdoll-slot-waist",
        ["Legs"] = "Interface\\Paperdoll\\ui-paperdoll-slot-legs",
        ["Feet"] = "Interface\\Paperdoll\\ui-paperdoll-slot-feet",
    }

    model.slots = {}

    for _, config in ipairs(slotConfig) do
        local btn = CreateFrame("Button", nil, model)
        btn:SetSize(34, 34)
        btn:SetPoint(config.point, config.x, config.y)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(slotTextures[config.slot])
        btn.bg = bg

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:Hide()
        btn.icon = icon
        
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetSize(60, 60)
        border:SetPoint("CENTER", 0, 0)
        border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        border:SetVertexColor(1, 1, 1, 0.5)
        
        btn:SetScript("OnEnter", function(self)
            if self.itemId then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. self.itemId)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
        
        model.slots[config.slot] = btn
    end

    local function UpdateSlots(setData)
        for _, btn in pairs(model.slots) do
            btn.icon:Hide()
            btn.itemId = nil
        end
        if not setData or not setData.items then return end
        
        for _, item in ipairs(setData.items) do
            local slotName = item.slot
            local btn = model.slots[slotName]
            if not btn and (slotName == "Robe") then btn = model.slots["Chest"] end
            
            if btn then
                btn.itemId = item.itemId
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(item.itemId)
                if texture then
                    btn.icon:SetTexture(texture)
                    btn.icon:Show()
                else
                    ns.QueryItem(item.itemId, function(id, success)
                        if success and btn.itemId == id then
                            local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(id)
                            btn.icon:SetTexture(tex)
                            btn.icon:Show()
                        end
                    end)
                end
            end
        end
    end

    local setNameText = model:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setNameText:SetPoint("BOTTOM", 0, 20)
    setNameText:SetText("")
    setNameText:SetTextColor(1, 0.82, 0)

    local setDescText = model:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    setDescText:SetPoint("TOP", setNameText, "BOTTOM", 0, -2)
    setDescText:SetText("")
    setDescText:SetTextColor(0.8, 0.8, 0.8)

    local applyBtn = CreateFrame("Button", nil, frame)
    applyBtn:SetSize(140, 30)
    applyBtn:SetPoint("TOP", model, "BOTTOM", 0, -5)

    local applyBtnBg = applyBtn:CreateTexture(nil, "BACKGROUND")
    applyBtnBg:SetAllPoints()
    applyBtnBg:SetTexture(0.1, 0.1, 0.1, 0.9)

    local applyBtnBorder = applyBtn:CreateTexture(nil, "BORDER")
    applyBtnBorder:SetPoint("TOPLEFT", -1, 1)
    applyBtnBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    applyBtnBorder:SetTexture(0.6, 0.5, 0.2, 0.8)

    local applyBtnHl = applyBtn:CreateTexture(nil, "HIGHLIGHT")
    applyBtnHl:SetAllPoints()
    applyBtnHl:SetTexture(1, 1, 1, 0.1)

    local applyBtnText = applyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    applyBtnText:SetPoint("CENTER")
    applyBtnText:SetText("Apply Set")
    applyBtnText:SetTextColor(1, 0.82, 0)

    applyBtn:SetScript("OnMouseDown", function()
        applyBtnBg:SetTexture(0.2, 0.2, 0.2, 1)
    end)
    applyBtn:SetScript("OnMouseUp", function()
        applyBtnBg:SetTexture(0.1, 0.1, 0.1, 0.9)
    end)

    local statsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsText:SetPoint("CENTER", model, "BOTTOM", 0, -45)
    statsText:SetText("Available Sets: 0")

    local function PickSetIconItemId(setData)
        if not setData.items or #setData.items == 0 then
            return nil
        end
        for _, item in ipairs(setData.items) do
            if item.slot == "Chest" or item.slot == "Robe" then
                return item.itemId
            end
        end
        for _, item in ipairs(setData.items) do
            if item.slot == "Shoulder" then
                return item.itemId
            end
        end
        for _, item in ipairs(setData.items) do
            if item.slot == "Head" then
                return item.itemId
            end
        end
        return setData.items[1].itemId
    end

    local function UpdatePreview()
        model:Reset()
        model:SetUnit("player")
        model:Undress()
        ShowModelBackground()

        if not selectedSet then
            return
        end

        local currentSet = selectedSet
        for _, item in ipairs(selectedSet.items) do
            if item.slot ~= "Main Hand" and item.slot ~= "Off-hand" and item.slot ~= "Ranged" then
                local itemId = item.itemId
                if GetItemInfo(itemId) then
                    model:TryOn(itemId)
                else
                    ns.QueryItem(itemId, function(qId, success)
                        if success and selectedSet == currentSet then
                            model:TryOn(qId)
                        end
                    end)
                end
            end
        end
    end

    SelectSet = function(setData)
        selectedSet = setData
        UpdatePreview()
        setNameText:SetText(setData.name)
        setDescText:SetText(setData.description or "")
        UpdateSlots(setData)

        for _, btn in ipairs(setsButtons) do
            if btn.setData == setData then
                btn.bg:SetTexture(0.6, 0.5, 0.2, 0.4)
                btn.text:SetTextColor(1, 1, 1)
            else
                btn.bg:SetTexture(0, 0, 0, 0)
                btn.text:SetTextColor(1, 0.82, 0)
            end
        end
    end

    BuildList = function()
        for _, btn in ipairs(setsButtons) do
            btn:Hide()
        end

        local sourceList = ns.itemSetsDB
        if currentFilter ~= "ALL" then
            sourceList = ns.itemSetsByClass[currentFilter] or {}
        end

        local allSets = {}
        if sourceList then
            for _, setData in ipairs(sourceList) do
                if searchQuery == "" or string.find(string.lower(setData.name), searchQuery, 1, true) then
                    table.insert(allSets, setData)
                end
            end
        end
        table.sort(allSets, function(a, b)
            return a.name < b.name
        end)

        statsText:SetText("Available Sets: " .. #allSets)

        local yOffset = 0
        for i, setData in ipairs(allSets) do
            local btn = setsButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, scrollChild)
                btn:SetSize(165, 32)

                local bg = btn:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetTexture(0, 0, 0, 0)
                btn.bg = bg

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                hl:SetBlendMode("ADD")
                hl:SetVertexColor(0.6, 0.5, 0.2, 0.3)

                local icon = btn:CreateTexture(nil, "ARTWORK")
                icon:SetSize(26, 26)
                icon:SetPoint("LEFT", 4, 0)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                btn.icon = icon

                local border = btn:CreateTexture(nil, "OVERLAY")
                border:SetSize(26, 26)
                border:SetPoint("CENTER", icon, "CENTER", 0, 0)
                border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
                border:SetVertexColor(0.6, 0.6, 0.6)

                local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
                text:SetJustifyH("LEFT")
                text:SetWidth(125)
                text:SetWordWrap(false)
                text:SetTextColor(1, 0.82, 0)
                btn.text = text

                setsButtons[i] = btn
            end

            btn:SetPoint("TOPLEFT", 0, -yOffset)
            btn.text:SetText(setData.name)
            btn.setData = setData
            btn:Show()

            local iconPath = "Interface\\Icons\\INV_Chest_Plate04"
            local iconItemId = PickSetIconItemId(setData)
            if iconItemId then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(iconItemId)
                if texture then
                    iconPath = texture
                else
                    ns.QueryItem(iconItemId, function(id, success)
                        if success then
                            local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(id)
                            if tex and btn:IsShown() and btn.setData == setData then
                                btn.icon:SetTexture(tex)
                            end
                        end
                    end)
                end
            end
            btn.icon:SetTexture(iconPath)

            btn:SetScript("OnClick", function()
                SelectSet(setData)
            end)

            yOffset = yOffset + 32
        end

        scrollChild:SetHeight(math.max(yOffset, 1))
    end

    applyBtn:SetScript("OnClick", function()
        if not selectedSet then
            return
        end
        PlaySound("LevelUp")
        local mainFrame = _G[addon]
        if not mainFrame then
            return
        end

        for _, item in ipairs(selectedSet.items) do
            local slot = mainFrame.slots[item.slot]
            if slot and slot.SetItem then
                slot:SetItem(item.itemId)
                ns.FlashMorphSlot(slot, "gold")
            end
        end
        if mainFrame.buttons and mainFrame.buttons.applyAll then
            mainFrame.buttons.applyAll:Click()
        end
        print("|cffF5C842<Transmorpher>|r: Applied set " .. selectedSet.name)
    end)

    if ns.InitializeItemSetsDB then
        ns.InitializeItemSetsDB()
    end
    SelectFilter("ALL")
    BuildList()
    model:SetUnit("player")
    model:Undress()
    ShowModelBackground()
    frame:HookScript("OnShow", function()
        UpdatePreview()
    end)
end
