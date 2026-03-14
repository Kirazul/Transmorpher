local addon, ns = ...

-- ============================================================
-- COMBAT PETS TAB — Curated/All Creatures dual mode + type filter
-- ============================================================

local mainFrame = ns.mainFrame
local hpetTab = mainFrame.tabs.combatPets
local ROW_HEIGHT = 28

local MODE_CURATED, MODE_ALL = 1, 2
local currentMode = MODE_CURATED

-- ========== TOP BAR ==========
local topBar = CreateFrame("Frame", nil, hpetTab)
topBar:SetPoint("TOPLEFT", 6, -4); topBar:SetPoint("RIGHT", -6, 0); topBar:SetHeight(24)
topBar:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", tile=true, tileSize=8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
topBar:SetBackdropColor(0.05, 0.055, 0.07, 0.93); topBar:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.78)

local btnModeCurated = ns.CreateGoldenButton("$parentHPetModeCurated", topBar)
btnModeCurated:SetSize(132, 20); btnModeCurated:SetPoint("LEFT", 4, 0)
do local ul = btnModeCurated:CreateTexture(nil, "OVERLAY"); ul:SetHeight(2)
    ul:SetPoint("BOTTOMLEFT", 8, 0); ul:SetPoint("BOTTOMRIGHT", -8, 0); ul:SetTexture(1, 0.82, 0); btnModeCurated.underline = ul end

local btnModeAll = ns.CreateGoldenButton("$parentHPetModeAll", topBar)
btnModeAll:SetSize(132, 20); btnModeAll:SetPoint("LEFT", btnModeCurated, "RIGHT", 4, 0)
do local ul = btnModeAll:CreateTexture(nil, "OVERLAY"); ul:SetHeight(2)
    ul:SetPoint("BOTTOMLEFT", 8, 0); ul:SetPoint("BOTTOMRIGHT", -8, 0); ul:SetTexture(1, 0.82, 0); ul:Hide(); btnModeAll.underline = ul end

-- Direct Display ID input
local directIDLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
directIDLabel:SetPoint("RIGHT", topBar, "RIGHT", -64, 0); directIDLabel:SetText("|cffC8AA6EDisplay ID:|r")

local directIDBox = CreateFrame("EditBox", "$parentHPetDirectID", topBar)
directIDBox:SetSize(56, 16); directIDBox:SetPoint("LEFT", directIDLabel, "RIGHT", 4, 0)
directIDBox:SetAutoFocus(false); directIDBox:SetMaxLetters(6); directIDBox:SetNumeric(true)
directIDBox:SetFont("Fonts\\FRIZQT__.TTF", 10); directIDBox:SetTextColor(0.95, 0.88, 0.65)
do
    local bg = directIDBox:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(0.03,0.03,0.04,0.95)
    local br = directIDBox:CreateTexture(nil, "BORDER"); br:SetPoint("TOPLEFT",-1,1); br:SetPoint("BOTTOMRIGHT",1,-1); br:SetTexture(0.70,0.58,0.24,0.55)
end
directIDBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
directIDBox:SetScript("OnEnterPressed", function(self)
    local id = tonumber(self:GetText())
    if id and id > 0 and ns.IsMorpherReady() then
        ns.SendMorphCommand("HPET_MORPH:"..id); ns.SendMorphCommand("HPET_SCALE:1.0")
        if TransmorpherCharacterState then TransmorpherCharacterState.HunterPetScale = 1.0 end
        ns.UpdateSpecialSlots()
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet morphed to display ID "..id)
        PlaySound("gsTitleOptionOK")
    end
    self:ClearFocus()
end)

-- ========== SEARCH & TYPE FILTER ==========
local searchContainer = CreateFrame("Frame", nil, hpetTab)
searchContainer:SetPoint("TOPLEFT", 6, -30); searchContainer:SetHeight(24)

local typeContainer = CreateFrame("Frame", nil, hpetTab)
typeContainer:SetPoint("TOPRIGHT", -6, -30); typeContainer:SetSize(200, 24)
typeContainer:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", tile=true, tileSize=8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
typeContainer:SetBackdropColor(0.05, 0.055, 0.07, 0.95); typeContainer:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.78)

searchContainer:SetPoint("RIGHT", typeContainer, "LEFT", -4, 0)
searchContainer:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", tile=true, tileSize=8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
searchContainer:SetBackdropColor(0.05, 0.055, 0.07, 0.95); searchContainer:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.78)

local hpSearchIcon = searchContainer:CreateTexture(nil, "OVERLAY")
hpSearchIcon:SetSize(14,14); hpSearchIcon:SetPoint("LEFT", 6, 0)
hpSearchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon"); hpSearchIcon:SetVertexColor(0.96, 0.82, 0.30)

local searchBox = CreateFrame("EditBox", "$parentHPetSearch", searchContainer)
searchBox:SetPoint("LEFT", hpSearchIcon, "RIGHT", 4, 0); searchBox:SetPoint("RIGHT", -20, 0); searchBox:SetHeight(18)
searchBox:SetAutoFocus(false); searchBox:SetMaxLetters(40)
searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11); searchBox:SetTextColor(0.95, 0.88, 0.65)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchHint:SetPoint("LEFT", 2, 0); searchHint:SetText("Search combat pets...")
searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
searchBox:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then searchHint:Show() end end)

local hpSearchClear = CreateFrame("Button", nil, searchContainer)
hpSearchClear:SetSize(14,14); hpSearchClear:SetPoint("RIGHT", -4, 0)
hpSearchClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon"); hpSearchClear:SetAlpha(0.5); hpSearchClear:Hide()
hpSearchClear:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
hpSearchClear:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
hpSearchClear:SetScript("OnClick", function() searchBox:SetText(""); searchBox:ClearFocus(); searchHint:Show(); hpSearchClear:Hide() end)

-- Type filter
local familyLabel = typeContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
familyLabel:SetPoint("LEFT", 6, 0); familyLabel:SetText("|cffC8AA6EType:|r")

local allFamilies = {}
local familySet = {}
if ns.combatPetsDB then
    for _, entry in ipairs(ns.combatPetsDB) do
        if not familySet[entry[2]] then familySet[entry[2]] = true; table.insert(allFamilies, entry[2]) end
    end
    table.sort(allFamilies)
end
table.insert(allFamilies, 1, "All Types")

local familyIdx = 1
local familyBtn = ns.CreateGoldenButton("$parentHPetFamilyBtn", typeContainer)
familyBtn:SetSize(130, 18); familyBtn:SetPoint("LEFT", familyLabel, "RIGHT", 4, 0)
familyBtn:SetText("|cffffd700All Types|r")

-- Current assignment status bar
local statusBar = CreateFrame("Frame", nil, hpetTab)
statusBar:SetPoint("TOPLEFT", 6, -56)
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
        statusLabel:SetText("|cff6a6050Combat Pet: None|r")
        return
    end

    local hpName = state.HunterPetName
    if not hpName and state.HunterPetDisplay and state.HunterPetDisplay > 0 then
        -- Try curated DB first
        for _, entry in ipairs(ns.combatPetsDB or {}) do
            if entry[3] == state.HunterPetDisplay then hpName = entry[1]; break end
        end
        -- Fallback to all creatures DB name if still not found
        if not hpName and ns.creatureDisplayDB then
            hpName = ns.creatureDisplayDB[state.HunterPetDisplay]
        end
    end
    
    local scaleText = state.HunterPetScale and string.format(" (Scale: %.1f)", state.HunterPetScale) or ""
    statusLabel:SetText("|cffffd700Combat Pet:|r " .. (hpName and ("|cffaaccff" .. hpName .. "|r") or "|cff6a6050None|r") .. "|cff888888" .. scaleText .. "|r")
end

-- ========== LIST (full width) ==========
local listBg = CreateFrame("Frame", "$parentHPetListBg", hpetTab)
listBg:SetPoint("TOPLEFT", 6, -76); listBg:SetPoint("BOTTOMRIGHT", -6, 38)
listBg:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=12, insets={left=2,right=2,top=2,bottom=2}})
listBg:SetBackdropColor(0.04, 0.03, 0.03, 0.9); listBg:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)

-- Column header
local headerFrame = CreateFrame("Frame", nil, listBg)
headerFrame:SetPoint("TOPLEFT", 4, -2); headerFrame:SetPoint("TOPRIGHT", -22, -2); headerFrame:SetHeight(18)
local headerName = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerName:SetPoint("LEFT", 34, 0); headerName:SetText("|cffC8AA6EName|r")
local headerType = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerType:SetPoint("CENTER", 60, 0); headerType:SetText("|cffC8AA6EType|r")
local headerID = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerID:SetPoint("RIGHT", -8, 0); headerID:SetText("|cffC8AA6EDisplay ID|r")
local headerSep = headerFrame:CreateTexture(nil, "ARTWORK")
headerSep:SetPoint("BOTTOMLEFT", 0, 0); headerSep:SetPoint("BOTTOMRIGHT", 0, 0); headerSep:SetHeight(1)
headerSep:SetTexture(0.50, 0.42, 0.18, 0.4)

local listScroll = CreateFrame("ScrollFrame", "$parentHPetListScroll", listBg, "UIPanelScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", 4, -20); listScroll:SetPoint("BOTTOMRIGHT", -22, 4)
local listContent = CreateFrame("Frame", "$parentHPetListContent", listScroll)
listContent:SetSize(listScroll:GetWidth(), 1); listScroll:SetScrollChild(listContent)

-- ========== BOTTOM BAR ==========
local bottomBar = CreateFrame("Frame", nil, hpetTab)
bottomBar:SetPoint("BOTTOMLEFT", 6, 2); bottomBar:SetPoint("BOTTOMRIGHT", -6, 2); bottomBar:SetHeight(34)
bottomBar:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Buttons\\WHITE8X8", tile=false, tileSize=0, edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
bottomBar:SetBackdropColor(0.08, 0.08, 0.08, 0.9); bottomBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
local bottomSepTop = bottomBar:CreateTexture(nil, "OVERLAY")
bottomSepTop:SetHeight(1); bottomSepTop:SetPoint("TOPLEFT", 4, 0); bottomSepTop:SetPoint("TOPRIGHT", -4, 0)
bottomSepTop:SetTexture(0.60, 0.50, 0.18, 0.35)

local btnSetHPet = ns.CreateGoldenButton("$parentBtnSetHPet", bottomBar)
btnSetHPet:SetSize(130, 24); btnSetHPet:SetPoint("LEFT", 6, 0)
btnSetHPet:SetText("|cffffd700Set Morph|r"); btnSetHPet:Disable()

local btnResetHPet = ns.CreateGoldenButton("$parentBtnResetHPet", bottomBar)
btnResetHPet:SetSize(100, 24); btnResetHPet:SetPoint("LEFT", btnSetHPet, "RIGHT", 4, 0)
btnResetHPet:SetText("|cffcc6666Reset|r")

local bottomSep = bottomBar:CreateTexture(nil, "ARTWORK")
bottomSep:SetSize(1, 18); bottomSep:SetPoint("LEFT", btnResetHPet, "RIGHT", 8, 0); bottomSep:SetTexture(0.50, 0.42, 0.18, 0.5)

local petSizeLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
petSizeLabel:SetPoint("LEFT", bottomSep, "RIGHT", 8, 0); petSizeLabel:SetText("|cffC8AA6EScale:|r")

local petSizeBox = CreateFrame("EditBox", "$parentHPetSizeInput", bottomBar)
petSizeBox:SetSize(36, 16); petSizeBox:SetPoint("LEFT", petSizeLabel, "RIGHT", 4, 0)
petSizeBox:SetAutoFocus(false); petSizeBox:SetMaxLetters(4); petSizeBox:SetText("1.0")
petSizeBox:SetFont("Fonts\\FRIZQT__.TTF", 10); petSizeBox:SetTextColor(0.95, 0.88, 0.65)
do
    local bg = petSizeBox:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(0,0,0,0.5)
    local br = petSizeBox:CreateTexture(nil, "BORDER"); br:SetPoint("TOPLEFT",-1,1); br:SetPoint("BOTTOMRIGHT",1,-1); br:SetTexture(0.50,0.42,0.18,0.6)
end
petSizeBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local btnPetSize = ns.CreateGoldenButton("$parentBtnHPetSize", bottomBar)
btnPetSize:SetSize(60, 22); btnPetSize:SetPoint("LEFT", petSizeBox, "RIGHT", 4, 0)
btnPetSize:SetText("|cffF5C842Resize|r")
btnPetSize:SetScript("OnClick", function()
    local scale = tonumber(petSizeBox:GetText())
    if scale and scale >= 0.1 and scale <= 10.0 and ns.IsMorpherReady() then
        ns.SendMorphCommand("HPET_SCALE:"..scale)
        if TransmorpherCharacterState then TransmorpherCharacterState.HunterPetScale = scale end
        if TransmorpherCharacterState and TransmorpherCharacterState.HunterPetDisplay and TransmorpherCharacterState.HunterPetDisplay > 0 then
            local did = TransmorpherCharacterState.HunterPetDisplay
            ns.SendMorphCommand("HPET_RESET")
            local t = CreateFrame("Frame"); t.elapsed = 0
            t:SetScript("OnUpdate", function(self, e) self.elapsed = self.elapsed + e
                if self.elapsed >= 0.1 then ns.SendMorphCommand("HPET_MORPH:"..did); ns.SendMorphCommand("HPET_SCALE:"..scale); self:SetScript("OnUpdate", nil) end
            end)
        end
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet scaled to "..scale)
        PlaySound("gsTitleOptionOK")
    end
end)
petSizeBox:SetScript("OnEnterPressed", function(self) btnPetSize:GetScript("OnClick")(); self:ClearFocus() end)

-- Result count
local resultCount = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
resultCount:SetPoint("RIGHT", -8, 0)

-- ========== STATE ==========
local hpetButtons, hpetSelectedIdx, hpetFilteredList = {}, nil, {}
local MAX_RESULTS = 200

local function FilterCurated(query)
    hpetFilteredList = {}
    local db = ns.combatPetsDB or {}
    local selFamily = allFamilies[familyIdx]
    local filterFamily = (selFamily ~= "All Types")
    if not query or query == "" then
        for i, entry in ipairs(db) do
            if not filterFamily or entry[2] == selFamily then
                table.insert(hpetFilteredList, {idx=i, name=entry[1], family=entry[2], displayID=entry[3]})
            end
        end
    else
        local q = query:lower()
        for i, entry in ipairs(db) do
            if (not filterFamily or entry[2] == selFamily) and (entry[1]:lower():find(q,1,true) or entry[2]:lower():find(q,1,true) or tostring(entry[3]):find(q,1,true)) then
                table.insert(hpetFilteredList, {idx=i, name=entry[1], family=entry[2], displayID=entry[3]})
            end
        end
    end
end

local creatureSortedList = nil
local function GetCreatureSortedList()
    if creatureSortedList then return creatureSortedList end
    creatureSortedList = {}
    local db = ns.creatureDisplayDB
    if not db then return creatureSortedList end
    for did, name in pairs(db) do table.insert(creatureSortedList, {did=did, name=name, nameLower=name:lower()}) end
    table.sort(creatureSortedList, function(a,b) return a.name < b.name end)
    return creatureSortedList
end

local function FilterAllCreatures(query)
    hpetFilteredList = {}
    local sorted = GetCreatureSortedList()
    if not query or query == "" or #query < 2 then
        local count = 0
        for _, entry in ipairs(sorted) do
            table.insert(hpetFilteredList, {idx=entry.did, name=entry.name, family="Creature", displayID=entry.did})
            count = count + 1; if count >= MAX_RESULTS then break end
        end
        return
    end
    local q, count = query:lower(), 0
    for _, entry in ipairs(sorted) do
        if entry.nameLower:find(q,1,true) or tostring(entry.did):find(q,1,true) then
            table.insert(hpetFilteredList, {idx=entry.did, name=entry.name, family="Creature", displayID=entry.did})
            count = count + 1; if count >= MAX_RESULTS then break end
        end
    end
end

local function BuildHPetList()
    for _, b in ipairs(hpetButtons) do b:Hide() end
    hpetButtons = {}; hpetSelectedIdx = nil; btnSetHPet:Disable()

    resultCount:SetText("|cffC8AA6E" .. #hpetFilteredList .. " results|r")

    local bY = 0
    for idx, entry in ipairs(hpetFilteredList) do
        local row = CreateFrame("Button", nil, listContent)
        row:SetSize(listContent:GetWidth()-4, ROW_HEIGHT); row:SetPoint("TOPLEFT", 2, -bY)
        local rowBg = row:CreateTexture(nil, "BACKGROUND"); rowBg:SetAllPoints()
        if idx % 2 == 0 then rowBg:SetTexture(1, 1, 1, 0.02) else rowBg:SetTexture(0, 0, 0, 0) end

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_HEIGHT-4, ROW_HEIGHT-4); icon:SetPoint("LEFT", 4, 0)
        local iconTex = "Interface\\Icons\\Ability_Hunter_BeastCall"
        if entry.family == "Creature" then iconTex = "Interface\\Icons\\INV_Misc_Head_Dragon_01" end
        icon:SetTexture(iconTex); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local iconBorder = row:CreateTexture(nil, "OVERLAY")
        iconBorder:SetSize(ROW_HEIGHT-2, ROW_HEIGHT-2); iconBorder:SetPoint("CENTER", icon)
        iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2"); iconBorder:SetTexCoord(0.2, 0.8, 0.2, 0.8)

        local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameStr:SetPoint("LEFT", icon, "RIGHT", 8, 0); nameStr:SetText("|cffffd700"..entry.name.."|r")
        nameStr:SetWidth(280); nameStr:SetJustifyH("LEFT")

        local famStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        famStr:SetPoint("LEFT", nameStr, "RIGHT", 4, 0); famStr:SetText("|cff8a7d6a"..entry.family.."|r")
        famStr:SetWidth(100); famStr:SetJustifyH("LEFT")

        local idStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        idStr:SetPoint("RIGHT", -8, 0); idStr:SetText("|cff6a6050"..entry.displayID.."|r")

        local defaultAlpha = (idx % 2 == 0) and 0.02 or 0

        row:SetScript("OnClick", function()
            if hpetSelectedIdx and hpetButtons[hpetSelectedIdx] then
                local defA = (hpetSelectedIdx % 2 == 0) and 0.02 or 0
                hpetButtons[hpetSelectedIdx].bg:SetTexture(1, 1, 1, defA)
            end
            hpetSelectedIdx = idx; rowBg:SetTexture(0.6, 0.48, 0.15, 0.3); btnSetHPet:Enable()
        end)
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnDoubleClick", function()
            hpetSelectedIdx = idx; rowBg:SetTexture(0.6, 0.48, 0.15, 0.3)
            if ns.IsMorpherReady() then
                ns.SendMorphCommand("HPET_MORPH:"..entry.displayID); ns.SendMorphCommand("HPET_SCALE:1.0")
                if TransmorpherCharacterState then 
                    TransmorpherCharacterState.HunterPetScale = 1.0 
                    TransmorpherCharacterState.HunterPetDisplay = entry.displayID
                    TransmorpherCharacterState.HunterPetName = entry.name
                end
                ns.UpdateSpecialSlots()
                UpdateStatusLabels()
                SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet morphed to "..entry.name.." ("..entry.displayID..")")
                PlaySound("gsTitleOptionOK")
            end
        end)
        row:SetScript("OnEnter", function()
            if hpetSelectedIdx ~= idx then rowBg:SetTexture(1, 1, 1, 0.06) end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:AddLine(entry.name)
            GameTooltip:AddLine("Type: "..entry.family, 1, 0.82, 0.1)
            GameTooltip:AddLine("Display ID: "..entry.displayID, 1,1,1)
            GameTooltip:AddLine("Click: Select  |  Double-click: Apply", 0.5,0.5,0.5); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if hpetSelectedIdx ~= idx then rowBg:SetTexture(1, 1, 1, defaultAlpha) end; GameTooltip:Hide()
        end)
        row.bg = rowBg; table.insert(hpetButtons, row); bY = bY + ROW_HEIGHT
    end
    listContent:SetHeight(math.max(1, bY))
end

local function RefreshList()
    if currentMode == MODE_CURATED then FilterCurated(searchBox:GetText()) else FilterAllCreatures(searchBox:GetText()) end
    BuildHPetList()
end

local function UpdateModeButtons()
    if currentMode == MODE_CURATED then
        btnModeCurated:SetText("|cffffd700Curated Pets|r"); btnModeAll:SetText("|cff888888All Creatures|r")
        if btnModeCurated.underline then btnModeCurated.underline:Show() end
        if btnModeAll.underline then btnModeAll.underline:Hide() end
        typeContainer:Show(); familyBtn:Enable(); familyLabel:SetAlpha(1)
        searchContainer:SetPoint("RIGHT", typeContainer, "LEFT", -4, 0)
        searchHint:SetText("Search combat pets...")
    else
        btnModeCurated:SetText("|cff888888Curated Pets|r"); btnModeAll:SetText("|cffffd700All Creatures|r")
        if btnModeCurated.underline then btnModeCurated.underline:Hide() end
        if btnModeAll.underline then btnModeAll.underline:Show() end
        typeContainer:Show(); familyBtn:Disable(); familyLabel:SetAlpha(0.4)
        searchContainer:SetPoint("RIGHT", typeContainer, "LEFT", -4, 0)
        searchHint:SetText("Search all creatures...")
    end
    if searchBox:GetText() == "" then searchHint:Show() end
end

btnModeCurated:SetScript("OnClick", function() currentMode = MODE_CURATED; UpdateModeButtons(); RefreshList() end)
btnModeAll:SetScript("OnClick", function() currentMode = MODE_ALL; UpdateModeButtons(); RefreshList() end)

familyBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
familyBtn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then familyIdx = 1
    else familyIdx = familyIdx + 1; if familyIdx > #allFamilies then familyIdx = 1 end end
    familyBtn:SetText("|cffffd700"..allFamilies[familyIdx].."|r"); RefreshList()
end)

local hpetSearchTimer = CreateFrame("Frame"); hpetSearchTimer:Hide(); hpetSearchTimer.elapsed = 0
hpetSearchTimer:SetScript("OnUpdate", function(self, dt) self.elapsed = self.elapsed + dt
    if self.elapsed >= 0.3 then self:Hide(); RefreshList() end
end)
searchBox:SetScript("OnTextChanged", function(self) hpetSearchTimer.elapsed = 0; hpetSearchTimer:Show()
    if self:GetText() ~= "" then hpSearchClear:Show() else hpSearchClear:Hide() end
end)

btnSetHPet:SetScript("OnClick", function()
    if hpetSelectedIdx and hpetFilteredList[hpetSelectedIdx] then
        local entry = hpetFilteredList[hpetSelectedIdx]
        if ns.IsMorpherReady() then
            ns.SendMorphCommand("HPET_MORPH:"..entry.displayID); ns.SendMorphCommand("HPET_SCALE:1.0")
            if TransmorpherCharacterState then 
                TransmorpherCharacterState.HunterPetScale = 1.0 
                TransmorpherCharacterState.HunterPetDisplay = entry.displayID
                TransmorpherCharacterState.HunterPetName = entry.name
            end
            ns.UpdateSpecialSlots()
            UpdateStatusLabels()
            SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet morphed to "..entry.name.." ("..entry.displayID..")")
        end; PlaySound("gsTitleOptionOK")
    end
end)

btnResetHPet:SetScript("OnClick", function()
    if ns.IsMorpherReady() then
        ns.SendMorphCommand("HPET_RESET")
        if TransmorpherCharacterState then
            TransmorpherCharacterState.HunterPetDisplay = nil
            TransmorpherCharacterState.HunterPetName = nil
            TransmorpherCharacterState.HunterPetScale = nil
        end
        ns.UpdateSpecialSlots()
        UpdateStatusLabels()
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Combat pet appearance reset!")
    end; PlaySound("gsTitleOptionOK")
end)

hpetTab:SetScript("OnShow", function()
    UpdateModeButtons()
    if #hpetFilteredList == 0 and currentMode == MODE_CURATED then RefreshList() end
    UpdateStatusLabels()
end)
