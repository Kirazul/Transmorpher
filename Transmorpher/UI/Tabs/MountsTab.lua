local addon, ns = ...

-- ============================================================
-- MOUNTS TAB — Searchable mount list with Ground/Flying/Reset
-- ============================================================

local mainFrame = ns.mainFrame
local mountTab = mainFrame.tabs.mounts
local ROW_HEIGHT = 28

-- ---------------------------------------------------------------------------
-- STATE & DATA LOGIC
-- ---------------------------------------------------------------------------
local mountButtons = {}
local mountSelectedIdx = nil
local mountFilteredList = {}
local mountTypeFilter = "ALL"

local GetSpellIcon = ns.GetSpellIcon

local function GetMountTypeTag(mountType)
    if mountType == "F" then
        return "|cff6699cc[Fly]|r"
    elseif mountType == "B" then
        return "|cff9988cc[Both]|r"
    else
        return "|cff669966[Gnd]|r"
    end
end

-- Forward declaration for SearchBox (needed for filtering)
local searchBox

local function FilterMounts(query)
    mountFilteredList = {}
    local db = ns.mountsDB or {}
    local q = (query or ""):lower()
    
    for i, entry in ipairs(db) do
        local mType = entry[5] or "G"
        local matchType = (mountTypeFilter == "ALL") or (mType == mountTypeFilter) or (mType == "B")
        
        if matchType then
            local name = entry[1]:lower()
            local displayID = tostring(entry[3])
            local typeName = (mType == "F" and "flying") or (mType == "B" and "both") or "ground"
            
            if q == "" or name:find(q, 1, true) or typeName:find(q, 1, true) or displayID:find(q, 1, true) then
                table.insert(mountFilteredList, { idx=i, name=entry[1], spellID=entry[2], displayID=entry[3], modelPath=entry[4], mountType=mType })
            end
        end
    end
    return mountFilteredList
end
ns.FilterMounts = FilterMounts

-- UI elements needed by BuildMountList
local listContent, resultCount, btnSetMount

local function BuildMountList()
    if not listContent then return end
    for _, b in ipairs(mountButtons) do b:Hide() end
    mountButtons = {}; mountSelectedIdx = nil
    if btnSetMount then btnSetMount:Disable() end

    if resultCount then
        resultCount:SetText("|cff6a6050" .. #mountFilteredList .. " mounts|r")
    end

    local bY = 0
    for idx, entry in ipairs(mountFilteredList) do
        local row = mountButtons[idx]
        if not row then
            row = CreateFrame("Button", nil, listContent)
            row:SetSize(listContent:GetWidth() - 4, ROW_HEIGHT)
            row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
            
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_HEIGHT-4, ROW_HEIGHT-4); row.icon:SetPoint("LEFT", 4, 0)
            
            local iconBorder = row:CreateTexture(nil, "OVERLAY")
            iconBorder:SetSize(ROW_HEIGHT-2, ROW_HEIGHT-2); iconBorder:SetPoint("CENTER", row.icon)
            iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2"); iconBorder:SetTexCoord(0.2, 0.8, 0.2, 0.8)

            row.nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.nameStr:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row.nameStr:SetPoint("RIGHT", row, "LEFT", 260, 0)
            row.nameStr:SetJustifyH("LEFT"); row.nameStr:SetWordWrap(false)

            row.typeStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.typeStr:SetPoint("LEFT", row, "LEFT", 280, 0)

            row.idStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.idStr:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            
            mountButtons[idx] = row
        end

        row:SetPoint("TOPLEFT", 2, -bY)
        row.bg:SetTexture(1, 1, 1, (idx % 2 == 0) and 0.02 or 0)
        row.icon:SetTexture(GetSpellIcon(entry.spellID)); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.nameStr:SetText("|cffffd700"..entry.name.."|r")
        row.typeStr:SetText(GetMountTypeTag(entry.mountType))
        row.idStr:SetText("|cff6a6050"..entry.displayID.."|r")

        row:SetScript("OnClick", function()
            if mountSelectedIdx and mountButtons[mountSelectedIdx] then
                mountButtons[mountSelectedIdx].bg:SetTexture(1, 1, 1, (mountSelectedIdx % 2 == 0) and 0.02 or 0)
            end
            mountSelectedIdx = idx; row.bg:SetTexture(0.6, 0.48, 0.15, 0.3); btnSetMount:Enable()
        end)
        row:SetScript("OnEnter", function()
            if mountSelectedIdx ~= idx then row.bg:SetTexture(1, 1, 1, 0.06) end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:AddLine(entry.name)
            GameTooltip:AddLine("Display ID: "..entry.displayID, 1, 1, 1)
            if entry.spellID > 0 then GameTooltip:AddLine("Spell ID: "..entry.spellID, 0.7, 0.7, 0.7) end
            local typeText = entry.mountType == "F" and "|cff6699ccFlying Mount|r" or (entry.mountType == "B" and "|cff9988ccFlying + Ground|r" or "|cff669966Ground Mount|r")
            GameTooltip:AddLine(typeText)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to select", 0.5, 0.5, 0.5); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if mountSelectedIdx ~= idx then row.bg:SetTexture(1, 1, 1, (idx % 2 == 0) and 0.02 or 0) end; GameTooltip:Hide()
        end)

        row:Show()
        bY = bY + ROW_HEIGHT
    end
    listContent:SetHeight(math.max(1, bY))
end
ns.BuildMountList = BuildMountList

-- ---------------------------------------------------------------------------
-- UI COMPONENTS
-- ---------------------------------------------------------------------------

-- Search Bar Container
local searchContainer = CreateFrame("Frame", nil, mountTab)
searchContainer:SetPoint("TOPLEFT", 6, -6); searchContainer:SetPoint("RIGHT", -6, 0); searchContainer:SetHeight(26)
searchContainer:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
})
searchContainer:SetBackdropColor(0.05, 0.055, 0.07, 0.95); searchContainer:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.78)

local searchIcon = searchContainer:CreateTexture(nil, "OVERLAY")
searchIcon:SetSize(14, 14); searchIcon:SetPoint("LEFT", 6, 0); searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon"); searchIcon:SetVertexColor(0.96, 0.82, 0.30)

-- Filter Buttons Container (Child of SearchContainer for anchoring)
local filterContainer = CreateFrame("Frame", nil, searchContainer)
filterContainer:SetSize(144, 22); filterContainer:SetPoint("LEFT", searchIcon, "RIGHT", 6, 0)

local function CreateFilterButton(text, filterVal, xOffset)
    local b = CreateFrame("Button", nil, filterContainer)
    b:SetSize(46, 18); b:SetPoint("LEFT", xOffset, 0)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(1, 1, 1, 0.05); b.bg = bg
    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); txt:SetPoint("CENTER"); txt:SetText(text); txt:SetTextColor(0.6, 0.5, 0.4); b.txt = txt
    
    b:SetScript("OnClick", function()
        mountTypeFilter = filterVal
        PlaySound("gsTitleOptionOK")
        for _, btn in ipairs(filterContainer.buttons) do
            if btn.val == mountTypeFilter then
                btn.bg:SetTexture(0.96, 0.82, 0.30, 0.3); btn.txt:SetTextColor(1, 0.9, 0.6)
            else
                btn.bg:SetTexture(1, 1, 1, 0.05); btn.txt:SetTextColor(0.6, 0.5, 0.4)
            end
        end
        FilterMounts(searchBox:GetText()); BuildMountList()
    end)
    b.val = filterVal
    return b
end

filterContainer.buttons = {
    CreateFilterButton("All", "ALL", 0),
    CreateFilterButton("Gnd", "G", 48),
    CreateFilterButton("Fly", "F", 96)
}

local function UpdateFilterButtons()
    for _, btn in ipairs(filterContainer.buttons) do
        if btn.val == mountTypeFilter then
            btn.bg:SetTexture(0.96, 0.82, 0.30, 0.3); btn.txt:SetTextColor(1, 0.9, 0.6)
        else
            btn.bg:SetTexture(1, 1, 1, 0.05); btn.txt:SetTextColor(0.6, 0.5, 0.4)
        end
    end
end
UpdateFilterButtons()

-- Search Box (Anchored to Filters)
searchBox = CreateFrame("EditBox", "$parentMountSearch", searchContainer)
searchBox:SetHeight(18); searchBox:SetPoint("LEFT", filterContainer, "RIGHT", 8, 0); searchBox:SetPoint("RIGHT", -80, 0)
searchBox:SetAutoFocus(false); searchBox:SetMaxLetters(40); searchBox:SetFont("Fonts\\FRIZQT__.TTF", 11); searchBox:SetTextColor(0.95, 0.88, 0.65)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchHint:SetPoint("LEFT", 2, 0); searchHint:SetText("Search mounts...")
searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide(); searchContainer:SetBackdropBorderColor(0.88, 0.74, 0.30, 0.95) end)
searchBox:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then searchHint:Show() end; searchContainer:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.78) end)

local searchClear = CreateFrame("Button", nil, searchContainer)
searchClear:SetSize(14, 14); searchClear:SetPoint("RIGHT", -4, 0); searchClear:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon"); searchClear:SetAlpha(0.5); searchClear:Hide()
searchClear:SetScript("OnClick", function() searchBox:SetText(""); searchBox:ClearFocus(); searchHint:Show(); searchClear:Hide() end)

resultCount = searchContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
resultCount:SetPoint("RIGHT", searchClear, "LEFT", -6, 0)

-- Status Bar
local statusBar = CreateFrame("Frame", nil, mountTab)
statusBar:SetPoint("TOPLEFT", 6, -34); statusBar:SetPoint("RIGHT", -6, 0); statusBar:SetHeight(18)
statusBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
statusBar:SetBackdropColor(0.03, 0.035, 0.04, 0.90); statusBar:SetBackdropBorderColor(0.40, 0.34, 0.16, 0.55)

local statusLabel = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusLabel:SetPoint("LEFT", 8, 0); statusLabel:SetTextColor(0.96, 0.82, 0.30)

local function UpdateStatusLabels()
    local state = TransmorpherCharacterState
    if not state then statusLabel:SetText("|cff6a6050Mount: None|r") return end
    if state.MountHidden then statusLabel:SetText("|cff888888Mount: Hidden|r") return end
    local mName = state.MountName
    if not mName and state.MountDisplay and state.MountDisplay > 0 then
        for _, entry in ipairs(ns.mountsDB or {}) do if entry[3] == state.MountDisplay then mName = entry[1]; break end end
    end
    statusLabel:SetText("|cffffd700Mount:|r " .. (mName and ("|cffaaccff" .. mName .. "|r") or "|cff6a6050None|r"))
end

-- List Background
local listBg = CreateFrame("Frame", "$parentMountListBg", mountTab)
listBg:SetPoint("TOPLEFT", 6, -54); listBg:SetPoint("BOTTOMRIGHT", -6, 38)
listBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
listBg:SetBackdropColor(0.04, 0.03, 0.03, 0.9); listBg:SetBackdropBorderColor(0.80, 0.65, 0.22, 0.85)

local headerFrame = CreateFrame("Frame", nil, listBg)
headerFrame:SetPoint("TOPLEFT", 4, -2); headerFrame:SetPoint("TOPRIGHT", -22, -2); headerFrame:SetHeight(18)
local headerName = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); headerName:SetPoint("LEFT", 34, 0); headerName:SetText("|cffA08D65Name|r")
local headerType = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); headerType:SetPoint("LEFT", 282, 0); headerType:SetText("|cffA08D65Type|r")
local headerID = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); headerID:SetPoint("RIGHT", -8, 0); headerID:SetText("|cffA08D65Display ID|r")

local listScroll = CreateFrame("ScrollFrame", "$parentMountListScroll", listBg, "UIPanelScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", 4, -20); listScroll:SetPoint("BOTTOMRIGHT", -22, 4)
listContent = CreateFrame("Frame", "$parentMountListContent", listScroll)
listContent:SetSize(listScroll:GetWidth(), 1); listScroll:SetScrollChild(listContent)

-- Bottom Buttons
btnSetMount = ns.CreateGoldenButton("$parentBtnSetMount", mountTab)
btnSetMount:SetSize(140, 26); btnSetMount:SetPoint("BOTTOMLEFT", 10, 4); btnSetMount:SetText("|cffffd700Set Mount|r"); btnSetMount:Disable()

local btnHideMount = ns.CreateGoldenButton("$parentBtnHideMount", mountTab)
btnHideMount:SetSize(120, 26); btnHideMount:SetPoint("LEFT", btnSetMount, "RIGHT", 6, 0); btnHideMount:SetText("|cff888888Hide|r")

local btnResetMount = ns.CreateGoldenButton("$parentBtnResetMount", mountTab)
btnResetMount:SetSize(120, 26); btnResetMount:SetPoint("LEFT", btnHideMount, "RIGHT", 6, 0); btnResetMount:SetText("|cffcc6666Reset|r")

local function AddButtonTooltip(btn, title, desc)
    btn:HookScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(title, 1, 0.82, 0.20); GameTooltip:AddLine(desc, 1, 1, 1, true); GameTooltip:Show() end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end
AddButtonTooltip(btnSetMount, "Set Mount", "Assign this appearance to all your mounts.")
AddButtonTooltip(btnHideMount, "Hide Mount", "Make your mount invisible.")
AddButtonTooltip(btnResetMount, "Reset Mount", "Clear all mount morphing assignments.")

-- Search Debounce
local mountSearchTimer = CreateFrame("Frame"); mountSearchTimer:Hide(); mountSearchTimer.elapsed = 0
mountSearchTimer:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed >= 0.3 then self:Hide(); FilterMounts(searchBox:GetText()); BuildMountList() end
end)
searchBox:SetScript("OnTextChanged", function(self)
    mountSearchTimer.elapsed = 0; mountSearchTimer:Show()
    if self:GetText() ~= "" then searchClear:Show() else searchClear:Hide() end
end)

btnSetMount:SetScript("OnClick", function()
    if mountSelectedIdx and mountFilteredList[mountSelectedIdx] then
        local entry = mountFilteredList[mountSelectedIdx]
        TransmorpherCharacterState.MountDisplay = entry.displayID; TransmorpherCharacterState.MountName = entry.name; TransmorpherCharacterState.MountHidden = false
        if ns.MountManager and ns.MountManager.ApplyCorrectMorph then ns.MountManager.ApplyCorrectMorph() end
        ns.UpdateSpecialSlots(); UpdateStatusLabels()
        if ns.BroadcastMorphState then ns.BroadcastMorphState() end
        SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Mount set to "..entry.name)
        PlaySound("gsTitleOptionOK")
    end
end)

btnHideMount:SetScript("OnClick", function()
    TransmorpherCharacterState.MountHidden = true
    if ns.MountManager and ns.MountManager.ApplyCorrectMorph then ns.MountManager.ApplyCorrectMorph() end
    UpdateStatusLabels()
    if ns.BroadcastMorphState then ns.BroadcastMorphState() end
    PlaySound("gsTitleOptionOK")
end)

btnResetMount:SetScript("OnClick", function()
    TransmorpherCharacterState.MountDisplay = nil; TransmorpherCharacterState.MountName = nil; TransmorpherCharacterState.MountHidden = false
    if TransmorpherCharacterState.Mounts then wipe(TransmorpherCharacterState.Mounts) end
    if ns.MountManager and ns.MountManager.ApplyCorrectMorph then ns.MountManager.ApplyCorrectMorph() end
    ns.UpdateSpecialSlots(); UpdateStatusLabels()
    if ns.BroadcastMorphState then ns.BroadcastMorphState() end
    PlaySound("gsTitleOptionOK")
end)

mountTab:SetScript("OnShow", function()
    if #mountFilteredList == 0 then FilterMounts(""); BuildMountList() end
    UpdateStatusLabels()
end)
