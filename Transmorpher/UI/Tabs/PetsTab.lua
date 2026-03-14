local addon, ns = ...

-- ============================================================
-- PETS TAB — Searchable pet list with Apply/Reset
-- ============================================================

local mainFrame = ns.mainFrame
local petTab = mainFrame.tabs.pets
local ROW_HEIGHT = 28

-- Search bar
local searchContainer = CreateFrame("Frame", nil, petTab)
searchContainer:SetPoint("TOPLEFT", 6, -6); searchContainer:SetPoint("RIGHT", -6, 0); searchContainer:SetHeight(26)
searchContainer:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = true, tileSize = 8, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
})
searchContainer:SetBackdropColor(0.05, 0.055, 0.07, 0.95)
searchContainer:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.78)

local searchIcon = searchContainer:CreateTexture(nil, "OVERLAY")
searchIcon:SetSize(14, 14); searchIcon:SetPoint("LEFT", 6, 0)
searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon"); searchIcon:SetVertexColor(0.96, 0.82, 0.30)

local searchBox = CreateFrame("EditBox", "$parentPetSearch", searchContainer)
searchBox:SetSize(480, 18); searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 4, 0)
searchBox:SetPoint("RIGHT", -24, 0); searchBox:SetAutoFocus(false); searchBox:SetMaxLetters(40)
searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11); searchBox:SetTextColor(0.95, 0.88, 0.65)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchHint:SetPoint("LEFT", 2, 0); searchHint:SetText("Search pets...")
searchBox:SetScript("OnEditFocusGained", function()
    searchHint:Hide()
    searchContainer:SetBackdropBorderColor(0.88, 0.74, 0.30, 0.95)
end)
searchBox:SetScript("OnEditFocusLost", function(self)
    if self:GetText() == "" then searchHint:Show() end
    searchContainer:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.78)
end)

local searchClear = CreateFrame("Button", nil, searchContainer)
searchClear:SetSize(14, 14); searchClear:SetPoint("RIGHT", -4, 0)
searchClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon"); searchClear:SetAlpha(0.5); searchClear:Hide()
searchClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
searchClear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
searchClear:SetScript("OnClick", function() searchBox:SetText(""); searchBox:ClearFocus(); searchHint:Show(); searchClear:Hide() end)

-- Result count
local resultCount = searchContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
resultCount:SetPoint("RIGHT", searchClear, "LEFT", -6, 0)

-- Current assignment status bar
local statusBar = CreateFrame("Frame", nil, petTab)
statusBar:SetPoint("TOPLEFT", 6, -34)
statusBar:SetPoint("RIGHT", -6, 0)
statusBar:SetHeight(18)
statusBar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = true, tileSize = 8, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
})
statusBar:SetBackdropColor(0.03, 0.035, 0.04, 0.90)
statusBar:SetBackdropBorderColor(0.40, 0.34, 0.16, 0.55)

local statusLabel = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusLabel:SetPoint("LEFT", 8, 0)
statusLabel:SetTextColor(0.96, 0.82, 0.30)

local function UpdateStatusLabels()
    local state = TransmorpherCharacterState
    if not state then
        statusLabel:SetText("|cff6a6050Pet: None|r")
        return
    end

    local pName = state.PetName
    if not pName and state.PetDisplay and state.PetDisplay > 0 then
        for _, entry in ipairs(ns.petsDB or {}) do
            if entry[3] == state.PetDisplay then pName = entry[1]; break end
        end
    end
    statusLabel:SetText("|cffffd700Pet:|r " .. (pName and ("|cffaaccff" .. pName .. "|r") or "|cff6a6050None|r"))
end

-- List background (full width)
local listBg = CreateFrame("Frame", "$parentPetListBg", petTab)
listBg:SetPoint("TOPLEFT", 6, -54); listBg:SetPoint("BOTTOMRIGHT", -6, 38)
listBg:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
})
listBg:SetBackdropColor(0.04, 0.03, 0.03, 0.9)
listBg:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)

-- Column header
local headerFrame = CreateFrame("Frame", nil, listBg)
headerFrame:SetPoint("TOPLEFT", 4, -2); headerFrame:SetPoint("TOPRIGHT", -22, -2); headerFrame:SetHeight(18)
local headerName = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerName:SetPoint("LEFT", 34, 0); headerName:SetText("|cffA08D65Name|r")
local headerID = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerID:SetPoint("RIGHT", -8, 0); headerID:SetText("|cffA08D65Display ID|r")
local headerSep = headerFrame:CreateTexture(nil, "ARTWORK")
headerSep:SetPoint("BOTTOMLEFT", 0, 0); headerSep:SetPoint("BOTTOMRIGHT", 0, 0); headerSep:SetHeight(1)
headerSep:SetTexture(0.50, 0.42, 0.18, 0.4)

local listScroll = CreateFrame("ScrollFrame", "$parentPetListScroll", listBg, "UIPanelScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", 4, -20); listScroll:SetPoint("BOTTOMRIGHT", -22, 4)

local listContent = CreateFrame("Frame", "$parentPetListContent", listScroll)
listContent:SetSize(listScroll:GetWidth(), 1)
listScroll:SetScrollChild(listContent)

-- Bottom buttons
local btnSetPet = ns.CreateGoldenButton("$parentBtnSetPet", petTab)
btnSetPet:SetSize(140, 26); btnSetPet:SetPoint("BOTTOMLEFT", 10, 4)
btnSetPet:SetText("|cffffd700Set Pet|r"); btnSetPet:Disable()

local btnResetPet = ns.CreateGoldenButton("$parentBtnResetPet", petTab)
btnResetPet:SetSize(120, 26); btnResetPet:SetPoint("LEFT", btnSetPet, "RIGHT", 8, 0)
btnResetPet:SetText("|cffcc6666Reset|r")

-- Button tooltips
local function AddButtonTooltip(btn, title, desc)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 0.82, 0.20)
        GameTooltip:AddLine(desc, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

AddButtonTooltip(btnSetPet, "Set Pet", "Assign this appearance to your non-combat pet.")
AddButtonTooltip(btnResetPet, "Reset Pet", "Clear all pet morphing assignments.")

-- State
local petButtons = {}
local petSelectedIdx = nil
local petFilteredList = {}

local GetSpellIcon = ns.GetSpellIcon

local function FilterPets(query)
    petFilteredList = {}
    local db = ns.petsDB or {}
    if not query or query == "" then
        for i, entry in ipairs(db) do
            table.insert(petFilteredList, { idx=i, name=entry[1], spellID=entry[2], displayID=entry[3], modelPath=entry[4] })
        end
    else
        local q = query:lower()
        for i, entry in ipairs(db) do
            if entry[1]:lower():find(q, 1, true) then
                table.insert(petFilteredList, { idx=i, name=entry[1], spellID=entry[2], displayID=entry[3], modelPath=entry[4] })
            end
        end
    end
    return petFilteredList
end

local function BuildPetList()
    for _, b in ipairs(petButtons) do b:Hide() end
    petButtons = {}; petSelectedIdx = nil; btnSetPet:Disable()

    resultCount:SetText("|cff6a6050" .. #petFilteredList .. " pets|r")

    local bY = 0
    for idx, entry in ipairs(petFilteredList) do
        local row = CreateFrame("Button", nil, listContent)
        row:SetSize(listContent:GetWidth() - 4, ROW_HEIGHT); row:SetPoint("TOPLEFT", 2, -bY)

        local rowBg = row:CreateTexture(nil, "BACKGROUND"); rowBg:SetAllPoints()
        if idx % 2 == 0 then rowBg:SetTexture(1, 1, 1, 0.02) else rowBg:SetTexture(0, 0, 0, 0) end

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_HEIGHT-4, ROW_HEIGHT-4); icon:SetPoint("LEFT", 4, 0)
        icon:SetTexture(GetSpellIcon(entry.spellID)); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local iconBorder = row:CreateTexture(nil, "OVERLAY")
        iconBorder:SetSize(ROW_HEIGHT-2, ROW_HEIGHT-2); iconBorder:SetPoint("CENTER", icon)
        iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2"); iconBorder:SetTexCoord(0.2, 0.8, 0.2, 0.8)

        local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameStr:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        nameStr:SetText("|cffffd700"..entry.name.."|r"); nameStr:SetJustifyH("LEFT")

        local idStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        idStr:SetPoint("RIGHT", -8, 0); idStr:SetText("|cff6a6050"..entry.displayID.."|r")

        local defaultAlpha = (idx % 2 == 0) and 0.02 or 0

        row:SetScript("OnClick", function()
            if petSelectedIdx and petButtons[petSelectedIdx] then
                local defA = (petSelectedIdx % 2 == 0) and 0.02 or 0
                petButtons[petSelectedIdx].bg:SetTexture(1, 1, 1, defA)
            end
            petSelectedIdx = idx; rowBg:SetTexture(0.6, 0.48, 0.15, 0.3); btnSetPet:Enable()
        end)
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnDoubleClick", function()
            petSelectedIdx = idx; rowBg:SetTexture(0.6, 0.48, 0.15, 0.3)
            if ns.IsMorpherReady() then
                ns.SendMorphCommand("PET_MORPH:"..entry.displayID)
                if TransmorpherCharacterState then
                    TransmorpherCharacterState.PetDisplay = entry.displayID
                    TransmorpherCharacterState.PetName = entry.name
                end
                ns.UpdateSpecialSlots()
                UpdateStatusLabels()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Pet morphed to "..entry.name.." ("..entry.displayID..")")
                PlaySound("gsTitleOptionOK")
            end
        end)
        row:SetScript("OnEnter", function()
            if petSelectedIdx ~= idx then rowBg:SetTexture(1, 1, 1, 0.06) end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:AddLine(entry.name)
            GameTooltip:AddLine("Display ID: "..entry.displayID, 1,1,1)
            if entry.spellID > 0 then GameTooltip:AddLine("Spell ID: "..entry.spellID, 0.7,0.7,0.7) end
            GameTooltip:AddLine("Click: Select  |  Double-click: Apply", 0.5,0.5,0.5); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if petSelectedIdx ~= idx then rowBg:SetTexture(1, 1, 1, defaultAlpha) end; GameTooltip:Hide()
        end)

        row.bg = rowBg; table.insert(petButtons, row); bY = bY + ROW_HEIGHT
    end
    listContent:SetHeight(math.max(1, bY))
end

-- Search debounce
local petSearchTimer = CreateFrame("Frame"); petSearchTimer:Hide(); petSearchTimer.elapsed = 0
petSearchTimer:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed >= 0.3 then self:Hide(); FilterPets(searchBox:GetText()); BuildPetList() end
end)
searchBox:SetScript("OnTextChanged", function(self)
    petSearchTimer.elapsed = 0; petSearchTimer:Show()
    if self:GetText() ~= "" then searchClear:Show() else searchClear:Hide() end
end)

btnSetPet:SetScript("OnClick", function()
    if petSelectedIdx and petFilteredList[petSelectedIdx] then
        local entry = petFilteredList[petSelectedIdx]
        if ns.IsMorpherReady() then
            ns.SendMorphCommand("PET_MORPH:"..entry.displayID)
            if TransmorpherCharacterState then
                TransmorpherCharacterState.PetDisplay = entry.displayID
                TransmorpherCharacterState.PetName = entry.name
            end
            ns.UpdateSpecialSlots()
            UpdateStatusLabels()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Pet morphed to "..entry.name.." ("..entry.displayID..")")
        end; PlaySound("gsTitleOptionOK")
    end
end)

btnResetPet:SetScript("OnClick", function()
    if ns.IsMorpherReady() then
        ns.SendMorphCommand("PET_RESET")
        ns.SendMorphCommand("HPET_RESET")
        ns.SendMorphCommand("HPET_SCALE:1.0")
        if TransmorpherCharacterState then 
            TransmorpherCharacterState.HunterPetScale = nil 
            TransmorpherCharacterState.PetDisplay = nil
            TransmorpherCharacterState.PetName = nil
        end
        ns.UpdateSpecialSlots()
        UpdateStatusLabels()
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Pet appearance reset!")
    end; PlaySound("gsTitleOptionOK")
end)

petTab:SetScript("OnShow", function()
    if #petFilteredList == 0 then FilterPets(""); BuildPetList() end
    UpdateStatusLabels()
end)
