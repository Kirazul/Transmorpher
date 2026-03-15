local addon, ns = ...

local mainFrame = ns.mainFrame
local settingsTab = mainFrame.tabs.settings
local _, classFileName = UnitClass("player")

local scrollFrame = CreateFrame("ScrollFrame", "$parentSettingsScroll", settingsTab, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 8, -8)
scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(scrollFrame:GetWidth(), 794)
scrollFrame:SetScrollChild(scrollChild)

local function applyCardStyle(card)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1}
    })
    card:SetBackdropColor(0.05, 0.055, 0.07, 0.92)
    card:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.75)

    local top = card:CreateTexture(nil, "OVERLAY")
    top:SetTexture("Interface\\Buttons\\WHITE8x8")
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetVertexColor(1, 0.92, 0.64, 0.22)

    local bottom = card:CreateTexture(nil, "OVERLAY")
    bottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", 1, 1)
    bottom:SetPoint("BOTTOMRIGHT", -1, 1)
    bottom:SetVertexColor(0, 0, 0, 0.7)
end

local function createCard(parent, title, y, height)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", 10, y)
    card:SetSize(parent:GetWidth() - 20, height)
    applyCardStyle(card)

    local titleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 12, -12)
    titleText:SetText(title)
    titleText:SetTextColor(1.00, 0.83, 0.24)
    titleText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

    local divider = card:CreateTexture(nil, "OVERLAY")
    divider:SetTexture("Interface\\Buttons\\WHITE8x8")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 12, -32)
    divider:SetPoint("TOPRIGHT", -12, -32)
    divider:SetVertexColor(0.62, 0.52, 0.22, 0.65)

    card.divider = divider
    return card
end

local function createCheckboxRow(parent, label, settingKey, y, tooltip, onToggle)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 12, y)
    row:SetSize(parent:GetWidth() - 24, 34)

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    rowBg:SetAllPoints()
    rowBg:SetVertexColor(1, 1, 1, 0)

    local cb = CreateFrame("CheckButton", "$parentCB_"..settingKey, row)
    cb:SetPoint("LEFT", 8, 0)
    cb:SetSize(22, 22)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:GetNormalTexture():SetVertexColor(0.80, 0.65, 0.22)
    cb:GetCheckedTexture():SetVertexColor(1.0, 0.82, 0.20)

    local labelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    labelText:SetText(label)
    labelText:SetTextColor(0.95, 0.88, 0.65)

    cb:SetScript("OnClick", function(self)
        local enabled = self:GetChecked() == 1
        ns.GetSettings()[settingKey] = enabled
        if onToggle then
            onToggle(enabled, self)
        end
        PlaySound("gsTitleOptionOK")
    end)
    cb:SetScript("OnShow", function(self)
        self:SetChecked(ns.GetSettings()[settingKey])
    end)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        rowBg:SetVertexColor(0.30, 0.25, 0.10, 0.22)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0.20)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        rowBg:SetVertexColor(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    row:SetScript("OnMouseDown", function()
        cb:Click()
    end)

    return cb
end

local persistenceCard = createCard(scrollChild, "Persistence", -14, 180)
createCheckboxRow(persistenceCard, "Persist morph across sessions", "saveMorphState", -42, "Automatically restore your character morph when you log in")
createCheckboxRow(persistenceCard, "Save mount morph per character", "saveMountMorph", -76, "Remember your mount morph for this character")
createCheckboxRow(persistenceCard, "Save pet morph per character", "savePetMorph", -110, "Remember your companion pet morph for this character")
createCheckboxRow(persistenceCard, "Save combat pet morph per character", "saveCombatPetMorph", -144, "Remember your hunter pet morph for this character")

local behaviorCard = createCard(scrollChild, "Behavior", -202, 146)
createCheckboxRow(behaviorCard, "Show Warlock Metamorphosis", "showMetamorphosis", -42, "Temporarily show the Metamorphosis demon form (suspend morph)", function(enabled)
    ns.SendRawMorphCommand("SET:META:"..(enabled and "1" or "0"))
    if classFileName == "WARLOCK" then
        local inForm = GetShapeshiftForm() > 0
        if inForm then
            if enabled and not ns.morphSuspended then
                ns.morphSuspended = true
                if not ns.dbwSuspended and not ns.vehicleSuspended then ns.SendRawMorphCommand("SUSPEND") end
            elseif not enabled and ns.morphSuspended then
                ns.morphSuspended = false
                if not ns.dbwSuspended and not ns.vehicleSuspended then ns.SendRawMorphCommand("RESUME") end
            end
        end
    end
end)
createCheckboxRow(behaviorCard, "Keep morph in shapeshift forms", "morphInShapeshift", -76, "Maintain your morph when shapeshifting (Druid forms, etc.)", function(enabled)
    ns.SendRawMorphCommand("SET:SHAPE:"..(enabled and "1" or "0"))
    if enabled and ns.morphSuspended then
        ns.morphSuspended = false
        if not ns.dbwSuspended and not ns.vehicleSuspended then ns.SendRawMorphCommand("RESUME") end
    elseif not enabled and ns.IsModelChangingForm() and not ns.morphSuspended then
        ns.morphSuspended = true
        if not ns.dbwSuspended and not ns.vehicleSuspended then ns.SendRawMorphCommand("SUSPEND") end
    end
end)
createCheckboxRow(behaviorCard, "Show Deathbringer's Will procs", "showDBWProc", -110, "Show the DBW transformation instead of your morph while the proc is active", function(enabled)
    ns.SendRawMorphCommand("SET:DBW:"..(enabled and "1" or "0"))
    if not enabled and ns.dbwSuspended then
        ns.dbwSuspended = false
        if not ns.morphSuspended and not ns.vehicleSuspended then
            ns.SendRawMorphCommand("RESUME")
            if ns.SendFullMorphState then ns.SendFullMorphState() end
        end
    end
end)

local syncCard = createCard(scrollChild, "Multiplayer Synchronization", -356, 80)
local function ApplySyncSettings()
    local settings = ns.GetSettings()
    local active = settings.enableWorldSync
    if ns.P2PSetEnabled then
        ns.P2PSetEnabled(active)
        return
    end
    if not active then
        if ns.ClearRemoteMorphs then ns.ClearRemoteMorphs() end
        if LeaveChannelByName then LeaveChannelByName("TransmorpherSync") end
        return
    end
    if settings.enableWorldSync then
        if JoinChannelByName then JoinChannelByName("TransmorpherSync") end
    end
end

createCheckboxRow(syncCard, "Activate Multiplayer Synchronization", "enableWorldSync", -42, "Enables synchronization of morphs with other players both in the world and in groups.", function(enabled)
    ApplySyncSettings()
end)

local interfaceCard = createCard(scrollChild, "Interface", -472, 112)
createCheckboxRow(interfaceCard, "Show Minimap Button", "showMinimapButton", -42, "Toggle the Transmorpher button on the minimap.", function(enabled)
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
end)
createCheckboxRow(interfaceCard, "Hide Character Info Button", "hidePaperdollButton", -76, "Toggle the Transmorpher button on the Character info frame.", function(enabled)
    if ns.UpdatePaperdollButtonVisibility then ns.UpdatePaperdollButtonVisibility() end
end)

local statusCard = createCard(scrollChild, "System Status", -592, 102)
local statusIcon = statusCard:CreateTexture(nil, "ARTWORK")
statusIcon:SetSize(30, 30)
statusIcon:SetPoint("TOPLEFT", 14, -50)
local statusTitle = statusCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
statusTitle:SetPoint("TOPLEFT", statusIcon, "TOPRIGHT", 10, 2)
local statusDesc = statusCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusDesc:SetPoint("TOPLEFT", statusTitle, "BOTTOMLEFT", 0, -4)
statusDesc:SetPoint("RIGHT", -12, 0)
statusDesc:SetJustifyH("LEFT")
statusDesc:SetTextColor(0.85, 0.85, 0.85)

local function UpdateDLLStatus()
    statusIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
    statusTitle:SetText("|cff4ACC4AMorpher DLL: LOADED|r")
    statusDesc:SetText("The morpher is active and ready to transform your character.")
    statusCard:SetBackdropBorderColor(0.29, 0.80, 0.29, 0.8)
end

local aboutCard = createCard(scrollChild, "About", -702, 160)
local infoText = aboutCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
infoText:SetPoint("TOPLEFT", 12, -42)
infoText:SetPoint("BOTTOMRIGHT", -12, 12)
infoText:SetJustifyH("LEFT")
infoText:SetJustifyV("TOP")
infoText:SetTextColor(0.95, 0.88, 0.65)
infoText:SetText("Transmorpher v"..ns.VERSION.."\n\nA transmog and morph system for WotLK 3.3.5a.\nTransform your character appearance, equipment, mounts, pets, enchants, and titles.\nIncludes optional multiplayer synchronization for shared visuals with other addon users.\nRequires dinput8.dll to function.")

settingsTab:SetScript("OnShow", function()
    UpdateDLLStatus()
end)
settingsTab:SetScript("OnUpdate", function(self, elapsed)
    if not self.statusUpdateTimer then return end
    self.statusUpdateTimer = self.statusUpdateTimer + elapsed
    if self.statusUpdateTimer >= 2 then
        UpdateDLLStatus()
        self.statusUpdateTimer = 0
    end
end)
settingsTab:HookScript("OnShow", function(self)
    self.statusUpdateTimer = 0
end)
settingsTab:SetScript("OnHide", function(self)
    self.statusUpdateTimer = nil
end)
