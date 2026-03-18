local addon, ns = ...

-- ============================================================
-- MAIN FRAME — Shell, border, title, tab system
-- ============================================================

local mainFrame = CreateFrame("Frame", addon, UIParent)
ns.mainFrame = mainFrame
table.insert(UISpecialFrames, mainFrame:GetName())

mainFrame:SetWidth(ns.Dimensions.mainWidth)
mainFrame:SetHeight(ns.Dimensions.mainHeight)
mainFrame:SetPoint("CENTER")
mainFrame:Hide()
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)

mainFrame:SetScript("OnShow", function()
    PlaySound("igCharacterInfoOpen")
    if mainFrame.slots then
        for _, slotName in pairs(ns.slotOrder) do
            local slot = mainFrame.slots[slotName]
            if slot then
                if slot.isMorphed and slot.morphedItemId then
                    ns.ShowMorphGlow(slot)
                elseif not slot.itemId then
                    if not (slotName == ns.rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(ns.playerClass)) then
                        local equippedId = ns.GetEquippedItemForSlot(slotName)
                        if equippedId then slot:SetItem(equippedId) end
                    end
                end
            end
        end
    end
    if mainFrame.enchantSlots then
        for _, es in pairs(mainFrame.enchantSlots) do
            if es.isMorphed then ns.ShowMorphGlow(es) end
        end
    end
    if ns.SyncDressingRoom then
        ns.SyncDressingRoom()
    end
    if ns.UpdateMorphStatusBar then
        ns.UpdateMorphStatusBar()
    end
end)
mainFrame:SetScript("OnHide", function() PlaySound("igCharacterInfoClose") end)

-- ============================================================
-- MAIN FRAME BACKGROUND & BORDER (Retail Flat Style)
-- ============================================================
mainFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = false, tileSize = 0, edgeSize = 2,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
})
mainFrame:SetBackdropColor(0.04, 0.04, 0.04, 0.98)
mainFrame:SetBackdropBorderColor(0.55, 0.45, 0.15, 0.75)

-- Optional drop shadow (fake)
local shadow = mainFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
shadow:SetPoint("TOPLEFT", -3, 3)
shadow:SetPoint("BOTTOMRIGHT", 3, -3)
shadow:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
shadow:SetVertexColor(0, 0, 0, 0.6)

-- Title Separator
local titleSep = mainFrame:CreateTexture(nil, "BORDER")
titleSep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
titleSep:SetPoint("TOPLEFT", 1, -30)
titleSep:SetPoint("TOPRIGHT", -1, -30)
titleSep:SetHeight(1)
titleSep:SetVertexColor(0.2, 0.2, 0.2, 1)

-- Main Vertical Separator (left side for preview, right side for tabs)
local separatorV = mainFrame:CreateTexture(nil, "BORDER")
separatorV:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
separatorV:SetPoint("TOPLEFT", 410, -30)
separatorV:SetPoint("BOTTOMLEFT", 410, 8)
separatorV:SetWidth(1)
separatorV:SetVertexColor(0.2, 0.2, 0.2, 1)

-- ============================================================
-- TITLE BAR
-- ============================================================
local mainFrameTitle = "|cffF5C842Transmorpher|r  |cff6a6050v" .. ns.VERSION .. "|r"

local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -8)
title:SetText(mainFrameTitle)
title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
title:SetShadowColor(0, 0, 0, 0.9)
title:SetShadowOffset(1, -1)

-- ============================================================
-- STATUS BAR
-- ============================================================
mainFrame.stats = CreateFrame("Frame", nil, mainFrame)
local stats = mainFrame.stats
stats:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
stats:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
stats:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
stats:SetPoint("BOTTOMLEFT", 415, 8)
stats:SetPoint("BOTTOMRIGHT", -6, 8)
stats:SetHeight(24)

mainFrame.morphStatus = stats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
mainFrame.morphStatus:SetPoint("CENTER")
mainFrame.morphStatus:SetText("")
mainFrame.morphStatus:SetTextColor(1.0, 0.84, 0.40, 1)

-- Status bar tooltip — hover for morph details
stats:EnableMouse(true)
stats:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("|cffF5C842Active Morphs|r", 1, 1, 1)
    if not TRANSMORPHER_DLL_LOADED then
        GameTooltip:AddLine("DLL not loaded", 1, 0.3, 0.3)
        GameTooltip:Show(); return
    end
    local morphedSlots = {}
    if mainFrame.slots then
        for _, slotName in pairs(ns.slotOrder or {}) do
            local slot = mainFrame.slots[slotName]
            if slot and slot.isMorphed then table.insert(morphedSlots, slotName) end
        end
    end
    if #morphedSlots > 0 then
        GameTooltip:AddLine("|cffF5C842Items:|r " .. table.concat(morphedSlots, ", "), 0.9, 0.8, 0.5, true)
    end
    if TransmorpherCharacterState then
        local s = TransmorpherCharacterState
        -- 1. Mount (Universal)
        local mountEntry = s.MountName or (s.MountDisplay and s.MountDisplay > 0 and ("ID " .. s.MountDisplay))
        if s.MountHidden then mountEntry = "|cff888888Hidden|r" end

        if mountEntry then
            GameTooltip:AddLine("|cff80cc80Mount:|r " .. mountEntry, 0.5, 0.8, 0.5, true)
        end

        -- 2. Morph
        if s.Morph then GameTooltip:AddLine("|cffd676ffMorph:|r Display ID " .. s.Morph, 0.84, 0.46, 1) end
        if s.PetDisplay then GameTooltip:AddLine("|cff88ddffPet:|r Display ID " .. s.PetDisplay, 0.53, 0.87, 1) end
        if s.HunterPetDisplay then GameTooltip:AddLine("|cffff8844CPet:|r Display ID " .. s.HunterPetDisplay, 1, 0.53, 0.27) end
        if s.EnchantMH then GameTooltip:AddLine("|cffffa040Enchant MH:|r ID " .. s.EnchantMH, 1, 0.63, 0.25) end
        if s.EnchantOH then GameTooltip:AddLine("|cffffa040Enchant OH:|r ID " .. s.EnchantOH, 1, 0.63, 0.25) end
        if s.TitleID then GameTooltip:AddLine("|cffcccc44Title:|r ID " .. s.TitleID, 0.8, 0.8, 0.27) end
    end
    if GameTooltip:NumLines() == 1 then
        GameTooltip:AddLine("No active morphs", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end)
stats:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Update morph status bar with active morph count
function ns.UpdateMorphStatusBar()
    if not mainFrame.morphStatus then return end
    local parts = {}
    local dllOk = TRANSMORPHER_DLL_LOADED

    if not dllOk then
        mainFrame.morphStatus:SetText("|cffff4444DLL Not Loaded|r")
        return
    end

    local itemCount = 0
    if TransmorpherCharacterState and TransmorpherCharacterState.Items then
        for _ in pairs(TransmorpherCharacterState.Items) do itemCount = itemCount + 1 end
    end
    if itemCount > 0 then table.insert(parts, "|cffF5C842" .. itemCount .. " items|r") end

    if TransmorpherCharacterState then
        if TransmorpherCharacterState.Morph then table.insert(parts, "|cffd676ffMorphed|r") end
        if TransmorpherCharacterState.MountDisplay or TransmorpherCharacterState.MountHidden then
            table.insert(parts, "|cff80cc80Mount|r")
        end
        if TransmorpherCharacterState.PetDisplay then table.insert(parts, "|cff88ddffPet|r") end
        if TransmorpherCharacterState.HunterPetDisplay then table.insert(parts, "|cffff8844CPet|r") end
        if TransmorpherCharacterState.EnchantMH or TransmorpherCharacterState.EnchantOH then table.insert(parts, "|cffffa040Enchant|r") end
        if TransmorpherCharacterState.TitleID then table.insert(parts, "|cffcccc44Title|r") end
    end

    if #parts > 0 then
        mainFrame.morphStatus:SetText(table.concat(parts, "  |cff555555\194\183|r  "))
    else
        mainFrame.morphStatus:SetText("|cff6a6050No active morphs|r")
    end
end

-- ============================================================
-- CLOSE BUTTON
-- ============================================================
mainFrame.buttons = {}
local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 1)
close:SetScript("OnClick", function(self) self:GetParent():Hide() end)
mainFrame.buttons.close = close

-- ============================================================
-- TAB SYSTEM
-- ============================================================
local TAB_NAMES = {"Preview", "Loadouts", "Mounts", "Pets", "CPets", "Morph", "Misc", "Settings"}
mainFrame.tabs = {}
mainFrame.tabContents = {}

do
    local tabs = {}
    local selectedTabIdx = 1
    local TAB_AREA_LEFT = 412
    local TAB_AREA_RIGHT = ns.Dimensions.mainWidth - 10
    local TAB_COUNT = #TAB_NAMES
    local TAB_H = 26
    local TAB_W = math.floor((TAB_AREA_RIGHT - TAB_AREA_LEFT) / TAB_COUNT)
    local TAB_TOP = -30

    local function UpdateTabAppearance()
        for i = 1, TAB_COUNT do
            local tabBtn = mainFrame.buttons["tab"..i]
            if i == selectedTabIdx then
                tabBtn.bg:SetTexture(0.12, 0.10, 0.07, 1)
                tabBtn.topLine:Show()
                tabBtn.botLine:Hide()
                tabBtn:GetFontString():SetTextColor(0.96, 0.78, 0.26, 1)
            else
                tabBtn.bg:SetTexture(0.06, 0.05, 0.04, 0.95)
                tabBtn.topLine:Hide()
                tabBtn.botLine:Show()
                tabBtn:GetFontString():SetTextColor(0.55, 0.50, 0.40, 1)
            end
        end
    end

    -- Tab fade animation
    local tabFadeFrame = CreateFrame("Frame")
    tabFadeFrame:Hide()
    local tabFadeState = {}

    tabFadeFrame:SetScript("OnUpdate", function(self, dt)
        local s = tabFadeState
        s.elapsed = s.elapsed + dt
        if s.phase == "out" then
            local progress = math.min(s.elapsed / 0.08, 1)
            s.oldTab:SetAlpha(1 - progress)
            if progress >= 1 then
                s.oldTab:Hide()
                s.oldTab:SetAlpha(1)
                s.phase = "in"
                s.elapsed = 0
                s.newTab:SetAlpha(0)
                s.newTab:Show()
            end
        elseif s.phase == "in" then
            local progress = math.min(s.elapsed / 0.12, 1)
            s.newTab:SetAlpha(progress)
            if progress >= 1 then
                s.newTab:SetAlpha(1)
                self:Hide()
            end
        end
    end)

    local function tab_OnClick(self)
        local newIdx = self:GetID()
        local prevTab = tabs[selectedTabIdx]
        local newTab = tabs[newIdx]

        if prevTab and prevTab ~= newTab and prevTab:IsShown() then
            tabFadeFrame:Hide()
            prevTab:SetAlpha(1)
            tabFadeState.oldTab = prevTab
            tabFadeState.newTab = newTab
            tabFadeState.phase = "out"
            tabFadeState.elapsed = 0
            tabFadeFrame:Show()
        else
            if prevTab then prevTab:Hide() end
            newTab:Show()
        end

        selectedTabIdx = newIdx
        PlaySound("gsTitleOptionOK")
        UpdateTabAppearance()
        -- Hide morph status bar on Preview tab (overlaps with page counter)
        if mainFrame.morphStatus and mainFrame.morphStatus:GetParent() then
            if selectedTabIdx == 1 then
                mainFrame.morphStatus:GetParent():Hide()
            else
                mainFrame.morphStatus:GetParent():Show()
            end
        end
    end
    ns.tab_OnClick = tab_OnClick

    for i = 1, TAB_COUNT do
        local btn = CreateFrame("Button", "$parentTab"..i, mainFrame)
        mainFrame.buttons["tab"..i] = btn
        btn:SetID(i)
        btn:SetSize(TAB_W, TAB_H)

        if i == 1 then
            btn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", TAB_AREA_LEFT, TAB_TOP)
        else
            btn:SetPoint("LEFT", mainFrame.buttons["tab"..(i-1)], "RIGHT", 0, 0)
        end
        if i == TAB_COUNT then
            btn:SetPoint("RIGHT", mainFrame, "RIGHT", -10, 0)
        end

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetTexture(0.06, 0.05, 0.04, 0.95)
        btn.bg = bg

        local topLine = btn:CreateTexture(nil, "OVERLAY")
        topLine:SetHeight(2)
        topLine:SetPoint("TOPLEFT"); topLine:SetPoint("TOPRIGHT")
        topLine:SetTexture(0.96, 0.78, 0.26, 1); topLine:Hide()
        btn.topLine = topLine

        local botLine = btn:CreateTexture(nil, "OVERLAY")
        botLine:SetHeight(1)
        botLine:SetPoint("BOTTOMLEFT"); botLine:SetPoint("BOTTOMRIGHT")
        botLine:SetTexture(0.35, 0.28, 0.14, 0.6)
        btn.botLine = botLine

        if i > 1 then
            local sep = btn:CreateTexture(nil, "OVERLAY")
            sep:SetWidth(1)
            sep:SetPoint("TOPLEFT", 0, -3); sep:SetPoint("BOTTOMLEFT", 0, 3)
            sep:SetTexture(0.3, 0.25, 0.15, 0.4)
        end

        local htex = btn:CreateTexture(nil, "HIGHLIGHT")
        htex:SetAllPoints(); htex:SetTexture(0.96, 0.78, 0.26, 0.15)
        btn:SetHighlightTexture(htex)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER"); fs:SetText(TAB_NAMES[i])
        fs:SetTextColor(0.55, 0.50, 0.40, 1)
        btn:SetFontString(fs)

        btn:SetScript("OnClick", tab_OnClick)

        local frame = CreateFrame("Frame", "$parentTab"..i.."Content", mainFrame)
        frame:SetPoint("TOPLEFT", TAB_AREA_LEFT, TAB_TOP - TAB_H)
        frame:SetPoint("BOTTOMRIGHT", -8, 36)
        frame:Hide()
        table.insert(tabs, frame)
    end

    -- Select first tab
    tab_OnClick(mainFrame.buttons["tab1"])

    -- Map tab keys
    mainFrame.tabs.preview    = tabs[1]
    mainFrame.tabs.appearances= tabs[2]
    mainFrame.tabs.mounts     = tabs[3]
    mainFrame.tabs.pets       = tabs[4]
    mainFrame.tabs.combatPets = tabs[5]
    mainFrame.tabs.morph      = tabs[6]
    mainFrame.tabs.env        = tabs[7]
    mainFrame.tabs.settings   = tabs[8]
    mainFrame.tabContents     = tabs
end
