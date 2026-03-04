local addon, ns = ...

local mainFrameTitle = "|cff00d4ffTransmorpher |cffffffff1.0.0|r"

local sex = UnitSex("player")
local _, raceFileName = UnitRace("player")
local _, classFileName = UnitClass("player")

local previewSetupVersion = "classic"

local armorSlots = {"Head", "Shoulder", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet"}
local backSlot = "Back"
local miscellaneousSlots = {"Tabard", "Shirt"}
local mainHandSlot = "Main Hand"
local offHandSlot = "Off-hand"
local rangedSlot = "Ranged"

local chestSlots = {"Chest", "Tabard", "Shirt"}

local addonMessagePrefix = "Transmorpher"
local slotOrder = { "Head", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs", "Feet", "Main Hand", "Off-hand", "Ranged",}

-- WoW equipment slot IDs for DLL morph calls
local slotToEquipSlotId = {
    ["Head"] = 1, ["Shoulder"] = 3, ["Back"] = 15, ["Chest"] = 5,
    ["Shirt"] = 4, ["Tabard"] = 19, ["Wrist"] = 9, ["Hands"] = 10,
    ["Waist"] = 6, ["Legs"] = 7, ["Feet"] = 8,
    ["Main Hand"] = 16, ["Off-hand"] = 17, ["Ranged"] = 18,
}

local slotTextures = {
    ["Head"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-head",
    ["Shoulder"] =  "Interface\\Paperdoll\\ui-paperdoll-slot-shoulder",
    ["Back"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
    ["Chest"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
    ["Shirt"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-shirt",
    ["Tabard"] =    "Interface\\Paperdoll\\ui-paperdoll-slot-tabard",
    ["Wrist"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-wrists",
    ["Hands"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-hands",
    ["Waist"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-waist",
    ["Legs"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-legs",
    ["Feet"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-feet",
    ["Main Hand"] = "Interface\\Paperdoll\\ui-paperdoll-slot-mainhand",
    ["Off-hand"] =  "Interface\\Paperdoll\\ui-paperdoll-slot-secondaryhand",
    ["Ranged"] =    "Interface\\Paperdoll\\ui-paperdoll-slot-ranged",
}

local slotSubclasses = {}

do
    for i, slot in ipairs(armorSlots) do slotSubclasses[slot] = {"Cloth", "Leather", "Mail", "Plate"} end
    for i, slot in ipairs(miscellaneousSlots) do slotSubclasses[slot] = {"Miscellaneous", } end
    slotSubclasses[backSlot] = {"Cloth", }
    slotSubclasses[mainHandSlot] = {
        "1H Axe", "1H Mace", "1H Sword", "1H Dagger", "1H Fist",
        "MH Axe", "MH Mace", "MH Sword", "MH Dagger", "MH Fist",
        "2H Axe", "2H Mace", "2H Sword", "Polearm", "Staff" }
    slotSubclasses[offHandSlot] = { "OH Axe", "OH Mace", "OH Sword", "OH Dagger", "OH Fist", "Shield", "Held in Off-hand"}
    slotSubclasses[rangedSlot] = {"Bow", "Crossbow", "Gun", "Wand", "Thrown"}
end

local defaultSlot = "Head"

local defaultArmorSubclass = {
    ["MAGE"] = "Cloth", ["PRIEST"] = "Cloth", ["WARLOCK"] = "Cloth",
    ["DRUID"] = "Leather", ["ROGUE"] = "Leather",
    ["HUNTER"] = "Mail", ["SHAMAN"] = "Mail",
    ["PALADIN"] = "Plate", ["WARRIOR"] = "Plate", ["DEATHKNIGHT"] = "Plate"
}

local defaultSettings = {
    dressingRoomBackgroundColor = {0.6, 0.6, 0.6, 1},
    dressingRoomBackgroundTexture = {
        [GetRealmName()] = {
            [GetUnitName("player")] = classFileName == "DEATHKNIGHT" and classFileName or raceFileName,
        },
    },
    previewSetup = "classic",
    showDressMeButton = true,
    showShortcutsInTooltip = true,
    hideHairOnCloakPreview = false,
    hideHairBeardOnChestPreview = false,
    useServerTimeInReceivedAppearances = false,
    announceAppearanceReceiving = true,
    ignoreUIScaling = false,
    saveMorphState = true,
}

local function GetSettings()
    local function copyTable(tableFrom)
        local result = {}
        for k, v in pairs(tableFrom) do
            if type(v) == "table" then result[k] = copyTable(v)
            else result[k] = v end
        end
        return result
    end
    if _G["TransmorpherSettings"] == nil then
        _G["TransmorpherSettings"] = copyTable(defaultSettings)
    else
        for k, v in pairs(defaultSettings) do
            if _G["TransmorpherSettings"][k] == nil then
                _G["TransmorpherSettings"][k] = type(v) == "table" and copyTable(v) or v
            end
        end
        if _G["TransmorpherSettings"].dressingRoomBackgroundTexture[GetRealmName()] == nil then
            _G["TransmorpherSettings"].dressingRoomBackgroundTexture[GetRealmName()] = {}
        end
        if _G["TransmorpherSettings"].dressingRoomBackgroundTexture[GetRealmName()][GetUnitName("player")] == nil then
            _G["TransmorpherSettings"].dressingRoomBackgroundTexture[GetRealmName()][GetUnitName("player")] = defaultSettings.dressingRoomBackgroundTexture[GetRealmName()][GetUnitName("player")]
        end
    end
    return _G["TransmorpherSettings"]
end

local function arrayHasValue(array, value)
    for i, v in ipairs(array) do
        if v == value then return true end
    end
    return false
end

---------------- MORPHER BRIDGE (STEALTH MODE) ----------------
-- Commands are sent via a global Lua variable that the C++ DLL
-- finds by scanning process memory. Each command has a sequence
-- number (VM001_...) so the DLL knows when a NEW command arrives.

local morphCmdSeq = 0
TRANSMORPHER_CMD = ""  -- Global variable the DLL scans for

local function TrackMorphCommand(cmd)
    if not TransmorpherCharacterState then TransmorpherCharacterState = {Items={}, Morph=nil, Scale=nil} end
    if not TransmorpherCharacterState.Items then TransmorpherCharacterState.Items = {} end

    for singleCmd in cmd:gmatch("[^|]+") do
        local parts = {strsplit(":", singleCmd)}
        local prefix = parts[1]
        
        if prefix == "ITEM" and parts[2] and parts[3] then
            TransmorpherCharacterState.Items[tonumber(parts[2])] = tonumber(parts[3])
        elseif prefix == "MORPH" and parts[2] then
            local val = tonumber(parts[2])
            if val and val > 0 then
                TransmorpherCharacterState.Morph = val
            end
        elseif prefix == "SCALE" and parts[2] then
            TransmorpherCharacterState.Scale = tonumber(parts[2])
        elseif prefix == "RESET" and parts[2] then
            if parts[2] == "ALL" then
                TransmorpherCharacterState = {Items={}, Morph=nil, Scale=nil}
            else
                TransmorpherCharacterState.Items[tonumber(parts[2])] = nil
            end
        end
    end
end

local function SendMorphCommand(cmd)
    TrackMorphCommand(cmd)
    if TRANSMORPHER_CMD == "" then
        TRANSMORPHER_CMD = cmd
    else
        TRANSMORPHER_CMD = TRANSMORPHER_CMD .. "|" .. cmd
    end
end

local function IsMorpherReady()
    return true
end

local dressingRoomBorderBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\AddOns\\Transmorpher\\images\\mirror-border",
    tile = false, tileSize = 16, edgeSize = 32,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

---------------- MAIN FRAME ----------------

local mainFrame = CreateFrame("Frame", addon, UIParent)
table.insert(UISpecialFrames, mainFrame:GetName())
do
    mainFrame:SetWidth(1045)
    mainFrame:SetHeight(505)
    mainFrame:SetPoint("CENTER")
    mainFrame:Hide()
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetScript("OnShow", function() PlaySound("igCharacterInfoOpen") end)
    mainFrame:SetScript("OnHide", function() PlaySound("igCharacterInfoClose") end)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(mainFrameTitle)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(2, -2)

    local titleBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    titleBg:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Title-Background")
    titleBg:SetPoint("TOPLEFT", 10, -7)
    titleBg:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT", -28, -24)
    titleBg:SetVertexColor(0.15, 0.15, 0.2, 1)

    local menuBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    menuBg:SetTexture("Interface\\WorldStateFrame\\WorldStateFinalScoreFrame-TopBackground")
    menuBg:SetTexCoord(0, 1, 0, 0.8125)
    menuBg:SetPoint("TOPLEFT", 10, -26)
    menuBg:SetPoint("RIGHT", -6, 0)
    menuBg:SetHeight(48)
    menuBg:SetVertexColor(0.1, 0.12, 0.15, 1)

    local frameBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    frameBg:SetTexture("Interface\\WorldStateFrame\\WorldStateFinalScoreFrame-TopBackground")
    frameBg:SetTexCoord(0, 0.5, 0, 0.8125)
    frameBg:SetPoint("TOPLEFT", menuBg, "BOTTOMLEFT")
    frameBg:SetPoint("TOPRIGHT", menuBg, "BOTTOMRIGHT")
    frameBg:SetPoint("BOTTOM", 0, 5)
    frameBg:SetVertexColor(0.08, 0.08, 0.12, 1)

    local topLeft = mainFrame:CreateTexture(nil, "BORDER")
    topLeft:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    topLeft:SetTexCoord(0.5, 0.625, 0, 1)
    topLeft:SetWidth(64) topLeft:SetHeight(64) topLeft:SetPoint("TOPLEFT")
    topLeft:SetVertexColor(0.3, 0.35, 0.45, 1)

    local topRight = mainFrame:CreateTexture(nil, "BORDER")
    topRight:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    topRight:SetTexCoord(0.625, 0.75, 0, 1)
    topRight:SetWidth(64) topRight:SetHeight(64) topRight:SetPoint("TOPRIGHT")
    topRight:SetVertexColor(0.3, 0.35, 0.45, 1)

    local top = mainFrame:CreateTexture(nil, "BORDER")
    top:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    top:SetTexCoord(0.25, 0.37, 0, 1)
    top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT")
    top:SetVertexColor(0.3, 0.35, 0.45, 1)

    local menuSepL = mainFrame:CreateTexture(nil, "BORDER")
    menuSepL:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    menuSepL:SetTexCoord(0.5, 0.5546875, 0.25, 0.53125)
    menuSepL:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT")
    menuSepL:SetWidth(28) menuSepL:SetHeight(18)
    menuSepL:SetVertexColor(0.3, 0.35, 0.45, 1)

    local menuSepR = mainFrame:CreateTexture(nil, "BORDER")
    menuSepR:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    menuSepR:SetTexCoord(0.7109375, 0.75, 0.25, 0.53125)
    menuSepR:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT")
    menuSepR:SetWidth(20) menuSepR:SetHeight(18)
    menuSepR:SetVertexColor(0.3, 0.35, 0.45, 1)

    local menuSepC = mainFrame:CreateTexture(nil, "BORDER")
    menuSepC:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    menuSepC:SetTexCoord(0.564453125, 0.671875, 0.25, 0.53125)
    menuSepC:SetPoint("TOPLEFT", menuSepL, "TOPRIGHT")
    menuSepC:SetPoint("BOTTOMRIGHT", menuSepR, "BOTTOMLEFT")
    menuSepC:SetVertexColor(0.3, 0.35, 0.45, 1)

    local botLeft = mainFrame:CreateTexture(nil, "BORDER")
    botLeft:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    botLeft:SetTexCoord(0.75, 0.875, 0, 1)
    botLeft:SetPoint("BOTTOMLEFT") botLeft:SetWidth(64) botLeft:SetHeight(64)
    botLeft:SetVertexColor(0.3, 0.35, 0.45, 1)

    local left = mainFrame:CreateTexture(nil, "BORDER")
    left:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    left:SetTexCoord(0, 0.125, 0, 1)
    left:SetPoint("TOPLEFT", menuSepL, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", botLeft, "TOPRIGHT")
    left:SetVertexColor(0.3, 0.35, 0.45, 1)

    local botRight = mainFrame:CreateTexture(nil, "BORDER")
    botRight:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    botRight:SetTexCoord(0.875, 1, 0, 1)
    botRight:SetPoint("BOTTOMRIGHT") botRight:SetWidth(64) botRight:SetHeight(64)
    botRight:SetVertexColor(0.3, 0.35, 0.45, 1)

    local right = mainFrame:CreateTexture(nil, "BORDER")
    right:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    right:SetTexCoord(0.125, 0.25, 0, 1)
    right:SetPoint("TOPRIGHT", menuSepR, "BOTTOMRIGHT", 4, 0)
    right:SetPoint("BOTTOMLEFT", botRight, "TOPLEFT", 4, 0)
    right:SetVertexColor(0.3, 0.35, 0.45, 1)

    local bot = mainFrame:CreateTexture(nil, "BORDER")
    bot:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    bot:SetTexCoord(0.38, 0.45, 0, 1)
    bot:SetPoint("BOTTOMLEFT", botLeft, "BOTTOMRIGHT")
    bot:SetPoint("TOPRIGHT", botRight, "TOPLEFT")
    bot:SetVertexColor(0.3, 0.35, 0.45, 1)

    local separatorV = mainFrame:CreateTexture(nil, "BORDER")
    separatorV:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    separatorV:SetTexCoord(0.23046875, 0.236328125, 0, 1)
    separatorV:SetPoint("TOPLEFT", 410, -72)
    separatorV:SetPoint("BOTTOM", 0, 32)
    separatorV:SetWidth(3)
    separatorV:SetVertexColor(0.2, 0.5, 0.8, 0.8)

    mainFrame.stats = CreateFrame("Frame", nil, mainFrame)
    local stats = mainFrame.stats
    stats:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 }
    })
    stats:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    stats:SetBackdropBorderColor(0.2, 0.5, 0.8, 0.8)
    stats:SetPoint("BOTTOMLEFT", 410, 8)
    stats:SetPoint("BOTTOMRIGHT", -6, 8)
    stats:SetHeight(24)

    -- Morph status text
    mainFrame.morphStatus = stats:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainFrame.morphStatus:SetPoint("CENTER")
    mainFrame.morphStatus:SetText("")
    mainFrame.morphStatus:SetTextColor(0.7, 0.9, 1, 1)

    mainFrame.buttons = {}

    local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function(self) self:GetParent():Hide() end)
    mainFrame.buttons.close = close
end

---------------- DRESSING ROOM ----------------

mainFrame.dressingRoom = ns.CreateDressingRoom(nil, mainFrame)

do
    local dr = mainFrame.dressingRoom
    dr:SetPoint("TOPLEFT", 10, -74)
    dr:SetSize(400, 400)

    local border = CreateFrame("Frame", nil, dr)
    border:SetAllPoints()
    border:SetBackdrop(dressingRoomBorderBackdrop)
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(0.3, 0.5, 0.8, 0.9)

    dr.backgroundTextures = {}
    for s in ("human,nightelf,dwarf,gnome,draenei,orc,scourge,tauren,troll,bloodelf,deathknight"):gmatch("%w+") do
        dr.backgroundTextures[s] = dr:CreateTexture(nil, "BACKGROUND")
        dr.backgroundTextures[s]:SetTexture("Interface\\AddOns\\Transmorpher\\images\\"..s)
        dr.backgroundTextures[s]:SetAllPoints()
        dr.backgroundTextures[s]:Hide()
    end
    dr.backgroundTextures["color"] = dr:CreateTexture(nil, "BACKGROUND")
    dr.backgroundTextures["color"]:SetAllPoints()
    dr.backgroundTextures["color"]:SetTexture(1, 1, 1)
    dr.backgroundTextures["color"]:Hide()

    local tip = dr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tip:SetPoint("BOTTOM", dr, "TOP", 0, 12)
    tip:SetJustifyH("CENTER") tip:SetJustifyV("BOTTOM")
    tip:SetText("\124cff66ff66Left Mouse:\124r rotate \124 \124cff66ff66Right Mouse:\124r pan\124n\124cff66ff66Wheel\124r or \124cff66ff66Alt + Right Mouse:\124r zoom")
    tip:SetTextColor(0.8, 0.9, 1, 1)
    tip:SetShadowColor(0, 0, 0, 1)
    tip:SetShadowOffset(1, -1)

    local defaultLight = {1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64}
    local shadowformLight = {1, 0, 0, 1, 0, 1, 0.16, 0, 0.23, 0}
    dr.shadowformEnabled = false
    dr.EnableShadowform = function(self)
        self:SetLight(unpack(shadowformLight))
        self:SetModelAlpha(0.75)
        self.shadowformEnabled = true
    end
    dr.DisableShadowform = function(self)
        self:SetLight(unpack(defaultLight))
        self:SetModelAlpha(1)
        self.shadowformEnabled = false
    end
end

---------------- BOTTOM BUTTONS ----------------

-- Apply All button (NEW - morphs all equipped preview items)
mainFrame.buttons.applyAll = CreateFrame("Button", "$parentButtonApplyAll", mainFrame, "UIPanelButtonTemplate2")
do
    local btn = mainFrame.buttons.applyAll
    btn:SetPoint("TOPLEFT", mainFrame.dressingRoom, "BOTTOMLEFT")
    btn:SetPoint("BOTTOM", mainFrame.stats, "BOTTOM", 0, 1)
    btn:SetWidth(mainFrame.dressingRoom:GetWidth()/4)
    btn:SetText("|cff66ff66Apply All|r")
    
    -- Modern button styling
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.1, 0.3, 0.1, 0.8)
    btn:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
    
    btn:SetScript("OnClick", function()
        if not IsMorpherReady() then
            SELECTED_CHAT_FRAME:AddMessage("|cff00d4ff<Transmorpher>|r: |cffff0000Morpher DLL not loaded! Place wow_morpher.dll in your WoW folder.|r")
            return
        end
        for _, slotName in pairs(slotOrder) do
            local slot = mainFrame.slots[slotName]
            if slot.itemId ~= nil and slotToEquipSlotId[slotName] then
                SendMorphCommand("ITEM:" .. slotToEquipSlotId[slotName] .. ":" .. slot.itemId)
            end
        end
        SELECTED_CHAT_FRAME:AddMessage("|cff00d4ff<Transmorpher>|r: All slots morphed!")
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 1, 0.5, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cff66ff66Apply All|r", 1, 1, 1)
        GameTooltip:AddLine("Apply all previewed items as morph to your character.", 0.7, 0.9, 1, 1, true)
        GameTooltip:AddLine("Requires wow_morpher.dll in your WoW folder.", 0.6, 0.6, 0.6, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        GameTooltip:Hide()
    end)
end

-- Reset Morph button (NEW)
mainFrame.buttons.resetMorph = CreateFrame("Button", "$parentButtonResetMorph", mainFrame, "UIPanelButtonTemplate2")
do
    local btn = mainFrame.buttons.resetMorph
    btn:SetPoint("TOPLEFT", mainFrame.buttons.applyAll, "TOPRIGHT")
    btn:SetWidth(mainFrame.buttons.applyAll:GetWidth())
    btn:SetText("|cffff8888Reset Morph|r")
    
    -- Modern button styling
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.3, 0.1, 0.1, 0.8)
    btn:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)
    
    btn:SetScript("OnClick", function()
        if IsMorpherReady() then
            SendMorphCommand("RESET:ALL")
            SELECTED_CHAT_FRAME:AddMessage("|cff00d4ff<Transmorpher>|r: All morphs reset!")
        end
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.5, 0.5, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cffff8888Reset Morph|r", 1, 1, 1)
        GameTooltip:AddLine("Revert all morphed slots back to your real equipped gear.", 0.7, 0.9, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)
        GameTooltip:Hide()
    end)
end

-- Reset Preview button
mainFrame.buttons.reset = CreateFrame("Button", "$parentButtonReset", mainFrame, "UIPanelButtonTemplate2")
do
    local btn = mainFrame.buttons.reset
    btn:SetPoint("TOPLEFT", mainFrame.buttons.resetMorph, "TOPRIGHT")
    btn:SetWidth(mainFrame.buttons.applyAll:GetWidth())
    btn:SetText("|cffaaddffReset Preview|r")
    
    -- Modern button styling
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.1, 0.15, 0.25, 0.8)
    btn:SetBackdropBorderColor(0.4, 0.6, 0.9, 1)
    
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:Reset()
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.6, 0.8, 1, 1)
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.6, 0.9, 1)
    end)
end

-- Undress button
mainFrame.buttons.undress = CreateFrame("Button", "$parentButtonUndress", mainFrame, "UIPanelButtonTemplate2")
do
    local btn = mainFrame.buttons.undress
    btn:SetPoint("TOPLEFT", mainFrame.buttons.reset, "TOPRIGHT")
    btn:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "BOTTOMRIGHT")
    btn:SetWidth(mainFrame.buttons.applyAll:GetWidth())
    btn:SetText("|cffffdd88Undress|r")
    
    -- Modern button styling
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.2, 0.15, 0.1, 0.8)
    btn:SetBackdropBorderColor(0.8, 0.6, 0.3, 1)
    
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:Undress()
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.8, 0.5, 1)
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.8, 0.6, 0.3, 1)
    end)
end

---------------- SHADOWFORM ----------------

mainFrame.buttons.shadowform = CreateFrame("Button", "$parentShadowformButton", mainFrame, "ItemButtonTemplate")
do
    local enableTex = "Interface\\Icons\\spell_shadow_shadowform"
    local disableTex = "Interface\\Icons\\spell_nature_wispsplode"
    local btn = mainFrame.buttons.shadowform
    btn:SetSize(28, 28)
    _G[btn:GetName().."NormalTexture"]:SetAllPoints()
    _G[btn:GetName().."NormalTexture"]:SetTexCoord(0.1875, 0.796875, 0.1875, 0.796875)
    btn:SetPoint("RIGHT", mainFrame.dressingRoom, "BOTTOMRIGHT", -16, 54)
    btn:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 1)
    local texture = btn:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints() texture:SetTexture(enableTex)
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self)
        PlaySound("gsTitleOptionOK")
        if not mainFrame.dressingRoom.shadowformEnabled then
            mainFrame.dressingRoom:EnableShadowform()
            texture:SetTexture(disableTex) self:LockHighlight()
        else
            mainFrame.dressingRoom:DisableShadowform()
            texture:SetTexture(enableTex) self:UnlockHighlight()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:ClearLines() GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Shadowform")
        GameTooltip:AddLine("A poor simulation that relies on the model's light setup.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:ClearLines() GameTooltip:Hide() end)
end

---------------- TABS ----------------

local TAB_NAMES = {"Items Preview", "Appearances", "Morph", "Settings"}
mainFrame.tabs = {}

do
    local tabs = {}
    local function tab_OnClick(self)
        local selectedTab = PanelTemplates_GetSelectedTab(self:GetParent())
        local tab = tabs[selectedTab]
        if tab ~= nil then tab:Hide() end
        PanelTemplates_SetTab(self:GetParent(), self:GetID())
        tabs[self:GetID()]:Show()
        PlaySound("gsTitleOptionOK")
        
        -- Update tab appearance for modern look
        for i = 1, #TAB_NAMES do
            local tabBtn = mainFrame.buttons["tab"..i]
            if i == self:GetID() then
                tabBtn:GetFontString():SetTextColor(0.4, 0.8, 1, 1)
            else
                tabBtn:GetFontString():SetTextColor(0.7, 0.7, 0.7, 1)
            end
        end
    end
    for i = 1, #TAB_NAMES do
        mainFrame.buttons["tab"..i] = CreateFrame("Button", "$parentTab"..i, mainFrame, "OptionsFrameTabButtonTemplate")
        local btn = mainFrame.buttons["tab"..i]
        btn:SetText(TAB_NAMES[i]) btn:SetID(i)
        if i == 1 then btn:SetPoint("BOTTOMLEFT", btn:GetParent(), "TOPLEFT", 410, -70)
        else btn:SetPoint("LEFT", _G[mainFrame:GetName().."Tab"..(i - 1)], "RIGHT") end
        btn:SetScript("OnClick", tab_OnClick)
        
        -- Modern tab styling
        btn:GetFontString():SetTextColor(0.7, 0.7, 0.7, 1)
        
        local frame = CreateFrame("Frame", "$parentTab"..i.."Content", mainFrame)
        frame:SetPoint("TOPLEFT", 410, -73) frame:SetPoint("BOTTOMRIGHT", -8, 28) frame:Hide()
        table.insert(tabs, frame)
    end
    PanelTemplates_SetNumTabs(mainFrame, #TAB_NAMES)
    tab_OnClick(_G[mainFrame:GetName().."Tab1"])
    mainFrame.tabs.preview = tabs[1]
    mainFrame.tabs.appearances = tabs[2]
    mainFrame.tabs.morph = tabs[3]
    mainFrame.tabs.settings = tabs[4]
end

---------------- SLOTS ----------------

mainFrame.slots = {}
mainFrame.selectedSlot = nil

local function getIndex(array, value)
    for i = 1, 10 do if array[i] == value then return i end end
    return nil
end

local function slot_OnShiftLeftClick(self)
    if self.itemId ~= nil then
        local _, link = GetItemInfo(self.itemId)
        if link then SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: "..link.." ("..self.itemId..")")
        else SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Item cannot be used for transmogrification.") end
    end
end

local function slot_OnControlLeftClick(self)
    if self.itemId ~= nil then ns.ShowWowheadURLDialog(self.itemId) end
end

local function slot_OnLeftClick(self)
    local selectedSlot = mainFrame.selectedSlot
    if selectedSlot ~= nil then selectedSlot:UnlockHighlight() end
    mainFrame.selectedSlot = self
    mainFrame.tabs.preview.subclassMenu:Update(self.slotName)
    if self.itemId ~= nil and getIndex({mainHandSlot, offHandSlot, rangedSlot}, self.slotName) then
        mainFrame.dressingRoom:TryOn(self.itemId)
    end
    self:LockHighlight()
end

local function slot_OnRightClick(self)
    self:RemoveItem()
end

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
    if self.itemId == nil then
        GameTooltip:AddLine(self.slotName)
    else
        local _, link = GetItemInfo(self.itemId)
        GameTooltip:SetHyperlink(link)
        if GetSettings().showShortcutsInTooltip then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Shift + Left Click:|r create a hyperlink.")
            GameTooltip:AddLine("|cff00ff00Right Click:|r undress the slot.")
            GameTooltip:AddLine("|cff00ff00Ctrl + Left Click:|r Wowhead URL.")
            GameTooltip:AddLine("|cff00ff00Alt + Left Click:|r apply morph to this slot.")
        end
    end
    GameTooltip:Show()
end

local function slot_OnLeave(self) GameTooltip:Hide() end

local function slot_Reset(self)
    local characterSlotName = self.slotName
    if characterSlotName == mainHandSlot then characterSlotName = "MainHand" end
    if characterSlotName == offHandSlot then characterSlotName = "SecondaryHand" end
    if characterSlotName == rangedSlot then characterSlotName = "Ranged" end
    if characterSlotName == backSlot then characterSlotName = "Back" end
    local slotId = GetInventorySlotInfo(characterSlotName.."Slot")
    local itemId = GetInventoryItemID("player", slotId)
    local name = GetItemInfo(itemId ~= nil and itemId or 0)
    if name ~= nil then self:SetItem(itemId) else self:RemoveItem() end
end

local function slot_RemoveItem(self)
    if self.itemId ~= nil then
        self.itemId = nil
        self.textures.empty:Show() self.textures.item:Hide()
        self:GetScript("OnEnter")(self)
        mainFrame.dressingRoom:Undress()
        for _, slot in pairs(mainFrame.slots) do
            if slot.itemId ~= nil then mainFrame.dressingRoom:TryOn(slot.itemId) end
        end
    end
end

local function slot_SetItem(self, itemId)
    self.itemId = itemId
    ns.QueryItem(itemId, function(queriedItemId, success)
        if queriedItemId == self.itemId and success then
            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(queriedItemId)
            self.textures.empty:Hide()
            self.textures.item:SetTexture(texture)
            self.textures.item:Show()
            mainFrame.dressingRoom:TryOn(queriedItemId)
        end
    end)
end

-- Build slots
do
    for slotName, texturePath in pairs(slotTextures) do
        local slot = CreateFrame("Button", "$parentSlot"..slotName, mainFrame, "ItemButtonTemplate")
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 1)
        slot:SetScript("OnClick", function(self, button)
            -- Alt+click = apply morph for this slot
            if button == "LeftButton" and IsAltKeyDown() and self.itemId and slotToEquipSlotId[self.slotName] then
                if IsMorpherReady() then
                    SendMorphCommand("ITEM:" .. slotToEquipSlotId[self.slotName] .. ":" .. self.itemId)
                    SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Morphed "..self.slotName.."!")
                else
                    SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: |cffff0000DLL not loaded!|r")
                end
                PlaySound("gsTitleOptionOK")
                return
            end
            slot_OnClick(self, button)
        end)
        slot:SetScript("OnEnter", slot_OnEnter)
        slot:SetScript("OnLeave", slot_OnLeave)
        slot.slotName = slotName
        mainFrame.slots[slotName] = slot
        slot.textures = {}
        slot.textures.empty = slot:CreateTexture(nil, "BACKGROUND")
        slot.textures.empty:SetTexture(texturePath) slot.textures.empty:SetAllPoints()
        slot.textures.item = slot:CreateTexture(nil, "BACKGROUND")
        slot.textures.item:SetAllPoints() slot.textures.item:Hide()
        slot.Reset = slot_Reset
        slot.SetItem = slot_SetItem
        slot.RemoveItem = slot_RemoveItem
    end

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
end

------- Hooks for slots and dressing room -------

local function btnReset_Hook()
    mainFrame.dressingRoom:Undress()
    for _, slot in pairs(mainFrame.slots) do
        if slot.slotName == rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(classFileName) then
            slot:RemoveItem()
        else slot:Reset() end
    end
    if mainFrame.dressingRoom.shadowformEnabled then mainFrame.dressingRoom:EnableShadowform() end
end

local function btnUndress_Hook()
    for _, slot in pairs(mainFrame.slots) do
        slot.itemId = nil
        slot.textures.empty:Show() slot.textures.item:Hide()
    end
end

local function tryOnFromSlots(dressUpModel)
    for _, slot in pairs(mainFrame.slots) do
        if slot.itemId ~= nil then dressUpModel:TryOn(slot.itemId) end
    end
end

local function dressingRoom_OnShow(self)
    self:Reset() self:Undress() tryOnFromSlots(self)
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

---------------- PREVIEW TAB ----------------

mainFrame.tabs.preview.list = ns.CreatePreviewList(mainFrame.tabs.preview)
mainFrame.tabs.preview.slider = CreateFrame("Slider", "$parentSlider", mainFrame.tabs.preview, "UIPanelScrollBarTemplateLightBorder")

do
    local previewTab = mainFrame.tabs.preview
    local list = mainFrame.tabs.preview.list
    local slider = mainFrame.tabs.preview.slider

    list:SetPoint("TOPLEFT") list:SetSize(601, 401)

    local label = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", list, "BOTTOM", 0, -5)
    label:SetJustifyH("CENTER") label:SetHeight(10)

    slider:SetPoint("TOPRIGHT", -6, -21) slider:SetPoint("BOTTOMRIGHT", -6, 21)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() - delta) end)
    slider:SetScript("OnMinMaxChanged", function(self, min, max)
        label:SetText(("Page: %s/%s"):format(self:GetValue(), max))
    end)

    slider.buttons = {}
    slider.buttons.up = _G[slider:GetName() .. "ScrollUpButton"]
    slider.buttons.down = _G[slider:GetName() .. "ScrollDownButton"]
    slider.buttons.up:SetScript("OnClick", function() slider:SetValue(slider:GetValue() - 1) PlaySound("gsTitleOptionOK") end)
    slider.buttons.down:SetScript("OnClick", function() slider:SetValue(slider:GetValue() + 1) PlaySound("gsTitleOptionOK") end)

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta) slider:SetValue(slider:GetValue() - delta) end)

    slider:SetScript("OnValueChanged", function(self, value)
        local _, max = self:GetMinMaxValues()
        label:SetText(("Page: %s/%s"):format(value, max))
    end)

    slider:SetMinMaxValues(0, 0) slider:SetValueStep(1)
end

---------------- Preview list logic ----------------

do
    local previewTab = mainFrame.tabs.preview
    local list = previewTab.list
    local slider = previewTab.slider
    local slotSubclassPage = {}
    for slot, _ in pairs(mainFrame.slots) do slotSubclassPage[slot] = {} end

    local currSlot, currSubclass = defaultSlot, defaultArmorSubclass[classFileName]
    local records

    local hideHairItemId = 10289
    local hideHairBeardItemId = 29943
    ns.QueryItem(hideHairItemId) ns.QueryItem(hideHairBeardItemId)

    local function hairBeardControl(slot)
        if slot == backSlot and GetSettings().hideHairOnCloakPreview then list:TryOn(hideHairItemId) end
        if arrayHasValue(chestSlots, slot) and GetSettings().hideHairBeardOnChestPreview then list:TryOn(hideHairBeardItemId) end
    end

    previewTab.Update = function(self, slot, subclass)
        slotSubclassPage[currSlot][currSubclass] = slider:GetValue() > 0 and slider:GetValue() or 1
        currSlot = slot currSubclass = subclass
        records = ns.GetSubclassRecords(slot, subclass)
        local itemIds = {} local selectedItemId
        for i=1, #records do
            local ids = records[i][1]
            table.insert(itemIds, ids[1])
            if selectedItemId == nil and mainFrame.slots[slot].itemId ~= nil and arrayHasValue(ids, mainFrame.slots[slot].itemId) then
                selectedItemId = ids[1]
            end
        end
        list:SetItems(itemIds)
        if selectedItemId ~= nil then list:SelectByItemId(selectedItemId) end

        local setup = ns.GetPreviewSetup(previewSetupVersion, raceFileName, sex, slot, subclass)
        list:SetupModel(setup.width, setup.height, setup.x, setup.y, setup.z, setup.facing, setup.sequence)

        list:TryOn(nil)
        local page = slotSubclassPage[slot][subclass] ~= nil and slotSubclassPage[slot][subclass] or 1
        local pageCount = list:GetPageCount()
        local _, sliderMax = slider:GetMinMaxValues()
        if page > sliderMax then slider:SetMinMaxValues(1, pageCount) end
        if slider:GetValue() ~= page then slider:SetValue(page)
        else list:SetPage(page) list:Update() end
        slider:SetMinMaxValues(1, pageCount)
        hairBeardControl(slot)
    end

    previewTab:SetScript("OnShow", function(self) self:Update(currSlot, currSubclass) end)

    slider:HookScript("OnValueChanged", function(self, value)
        list:SetPage(value) list:Update() hairBeardControl(currSlot)
    end)

    local selectedInRecord = {}
    local enteredButton
    local tabDummy = CreateFrame("Button", addon.."PreviewListTabDummy", previewTab)

    list.onEnter = function(self)
        local recordIndex = self:GetParent().itemIndex
        local ids = records[recordIndex][1]
        local names = records[recordIndex][2]
        GameTooltip:Hide() GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT") GameTooltip:ClearLines()
        GameTooltip:AddLine("This appearance is provided by:", 1, 1, 1) GameTooltip:AddLine(" ")
        local selectedIndex = selectedInRecord[ids[1]] ~= nil and selectedInRecord[ids[1]] or 1
        for i, id in ipairs(ids) do
            GameTooltip:AddLine((i == selectedIndex and "> " or "- ")..names[i]..(id == mainFrame.selectedSlot.itemId and " *"or ""))
        end
        if GetSettings().showShortcutsInTooltip then
            GameTooltip:AddLine("\n|cff00ff00Left Click:|r try on.")
            if #ids > 1 then GameTooltip:AddLine("|cff00ff00Tab:|r choose item.") end
            GameTooltip:AddLine("|cff00ff00Shift + Left:|r hyperlink.")
            GameTooltip:AddLine("|cff00ff00Ctrl + Left:|r Wowhead URL.")
        end
        GameTooltip:Show()
        SetOverrideBindingClick(tabDummy, true, "TAB", tabDummy:GetName(), "RightButton")
        enteredButton = self
    end

    list.onLeave = function(self)
        ClearOverrideBindings(tabDummy)
        GameTooltip:ClearLines() GameTooltip:Hide() enteredButton = nil
    end

    tabDummy:SetScript("OnClick", function()
        if enteredButton ~= nil then
            local recordIndex = enteredButton:GetParent().itemIndex
            local ids = records[recordIndex][1]
            if #ids > 1 then
                if selectedInRecord[ids[1]] == nil then selectedInRecord[ids[1]] = 2
                else selectedInRecord[ids[1]] = selectedInRecord[ids[1]] < #ids and selectedInRecord[ids[1]] + 1 or 1 end
            end
            list.onEnter(enteredButton)
        end
    end)

    list.onItemClick = function(self, button)
        local recordIndex = self:GetParent().itemIndex
        local ids = records[recordIndex][1]
        local selectedIndex = selectedInRecord[ids[1]] ~= nil and selectedInRecord[ids[1]] or 1
        local itemId = ids[selectedIndex]
        if IsShiftKeyDown() then
            local names = records[recordIndex][2]
            local color = names[selectedIndex]:sub(1, 10)
            local name = names[selectedIndex]:sub(11, -3)
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: "..color.."\124Hitem:"..itemId..":::::::|h["..name.."]\124h\124r".." ("..itemId..")")
        elseif IsControlKeyDown() then
            ns.ShowWowheadURLDialog(itemId)
        else
            mainFrame.selectedSlot:SetItem(itemId)
        end
        list.onEnter(self)
    end
end

---------------- SUBCLASS MENU ----------------

mainFrame.tabs.preview.subclassMenu = CreateFrame("Frame", "$parentSubclassMenu", mainFrame.tabs.preview, "UIDropDownMenuTemplate")
do
    local previewTab = mainFrame.tabs.preview
    local menu = mainFrame.tabs.preview.subclassMenu
    menu:SetPoint("TOPRIGHT", -120, 38)
    UIDropDownMenu_JustifyText(menu, "LEFT")

    local slotSelectedSubclass = {}
    for i, slot in ipairs(armorSlots) do slotSelectedSubclass[slot] = defaultArmorSubclass[classFileName] end
    for i, slot in ipairs(miscellaneousSlots) do slotSelectedSubclass[slot] = "Miscellaneous" end
    slotSelectedSubclass[backSlot] = slotSubclasses[backSlot][1]
    slotSelectedSubclass[mainHandSlot] = slotSubclasses[mainHandSlot][1]
    slotSelectedSubclass[offHandSlot] = slotSubclasses[offHandSlot][1]
    slotSelectedSubclass[rangedSlot] = slotSubclasses[rangedSlot][1]

    local function menu_OnClick(self, slot, subclass)
        previewTab:Update(slot, subclass)
        slotSelectedSubclass[slot] = subclass
        UIDropDownMenu_SetText(menu, subclass)
    end

    local initializer = { ["slot"] = nil,
        ["__call"] = function(self, frame)
            local info = UIDropDownMenu_CreateInfo()
            for i, subclass in ipairs(slotSubclasses[self.slot]) do
                info.text = subclass
                info.checked = subclass == UIDropDownMenu_GetText(frame)
                info.arg1 = self.slot info.arg2 = subclass info.func = menu_OnClick
                UIDropDownMenu_AddButton(info)
            end
        end,
    }
    setmetatable(initializer, initializer)

    menu.Update = function(self, slot)
        if #slotSubclasses[slot] > 1 then UIDropDownMenu_EnableDropDown(self)
        else UIDropDownMenu_DisableDropDown(self) end
        UIDropDownMenu_SetText(self, slotSelectedSubclass[slot])
        initializer.slot = slot
        previewTab:Update(slot, slotSelectedSubclass[slot])
        UIDropDownMenu_Initialize(self, initializer)
    end
end

---------------- APPEARANCES TAB ----------------

mainFrame.tabs.appearances.saved = CreateFrame("Frame", "$parentSaved", mainFrame.tabs.appearances)
do
    local appearancesTab = mainFrame.tabs.appearances
    local frame = appearancesTab.saved
    frame:SetPoint("TOPLEFT", 5, -30) frame:SetPoint("BOTTOM", 0, 30) frame:SetWidth(280)
    frame:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }})
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    frame:SetBackdropBorderColor(0.2, 0.5, 0.8, 0.8)

    local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8) scrollFrame:SetPoint("BOTTOMLEFT", 8, 8)
    scrollFrame:SetWidth(frame:GetWidth() - 12)

    local btnSave = CreateFrame("Button", "$parentButtonSave", scrollFrame, "UIPanelButtonTemplate2")
    btnSave:SetSize(70, 20) btnSave:SetPoint("CENTER", frame, "TOP", 0, 14)
    btnSave:SetText("Save") btnSave:SetScript("OnClick", function() PlaySound("gsTitleOptionOK") end) btnSave:Disable()

    local btnSaveAs = CreateFrame("Button", "$parentButtonSaveAs", scrollFrame, "UIPanelButtonTemplate2")
    btnSaveAs:SetSize(70, 20) btnSaveAs:SetPoint("LEFT", frame, "TOPLEFT", 0, 14)
    btnSaveAs:SetText("Save As...") btnSaveAs:SetScript("OnClick", function() PlaySound("gsTitleOptionOK") end)

    local btnRemove = CreateFrame("Button", "$parentButtonRemove", scrollFrame, "UIPanelButtonTemplate2")
    btnRemove:SetSize(70, 20) btnRemove:SetPoint("RIGHT", frame, "TOPRIGHT", 0, 14)
    btnRemove:SetText("Remove") btnRemove:SetScript("OnClick", function() PlaySound("gsTitleOptionOK") end) btnRemove:Disable()

    local btnTryOn = CreateFrame("Button", "$parentButtonTryOn", scrollFrame, "UIPanelButtonTemplate2")
    btnTryOn:SetSize(70, 20) btnTryOn:SetPoint("LEFT", frame, "BOTTOMLEFT", 0, -12)
    btnTryOn:SetText("Try On") btnTryOn:SetScript("OnClick", function() PlaySound("gsTitleOptionOK") end) btnTryOn:Disable()

    -- NEW: Apply Look button
    local btnApplyLook = CreateFrame("Button", "$parentButtonApplyLook", scrollFrame, "UIPanelButtonTemplate2")
    btnApplyLook:SetSize(70, 20) btnApplyLook:SetPoint("CENTER", frame, "BOTTOM", 0, -12)
    btnApplyLook:SetText("|cff00ff00Apply|r")
    btnApplyLook:SetScript("OnClick", function() PlaySound("gsTitleOptionOK") end) btnApplyLook:Disable()

    local listFrame = ns.CreateListFrame("$parentSavedLooks", nil, scrollFrame)
    listFrame:SetWidth(scrollFrame:GetWidth())
    listFrame:SetScript("OnShow", function(self)
        if self.selected == nil then
            btnTryOn:Disable() btnRemove:Disable() btnSave:Disable() btnApplyLook:Disable()
        else
            btnTryOn:Enable() btnRemove:Enable() btnSave:Enable() btnApplyLook:Enable()
        end
    end)
    listFrame.onSelect = function()
        btnTryOn:Enable() btnRemove:Enable() btnSave:Enable() btnApplyLook:Enable()
    end

    local function slots2ItemList()
        local items = {}
        for _, slotName in pairs(slotOrder) do
            if mainFrame.slots[slotName].itemId ~= nil then table.insert(items, mainFrame.slots[slotName].itemId)
            else table.insert(items, 0) end
        end
        return items
    end

    local function buildList()
        local savedLooks = _G["TransmorpherSavedLooks"]
        _G["TransmorpherSavedLooks"] = {}
        local names, items = {}, {}
        for _, look in pairs(savedLooks) do
            table.insert(names, look.name) items[look.name] = look.items
        end
        table.sort(names)
        for _, name in ipairs(names) do
            listFrame:AddItem(name)
            table.insert(_G["TransmorpherSavedLooks"], {["name"] = name, ["items"] = items[name]})
        end
    end

    listFrame:RegisterEvent("ADDON_LOADED")
    listFrame:SetScript("OnEvent", function(self, event, addonName)
        if addonName == addon and event == "ADDON_LOADED" then
            if _G["TransmorpherSavedLooks"] == nil then _G["TransmorpherSavedLooks"] = {} end
            buildList()
            scrollFrame:SetScrollChild(listFrame)
        end
    end)

    btnTryOn:HookScript("OnClick", function()
        local savedLooks = _G["TransmorpherSavedLooks"]
        local id = listFrame.buttons[listFrame:GetSelected()]:GetID()
        for index, slotName in pairs(slotOrder) do
            local itemId = savedLooks[id].items[index]
            if itemId ~= nil and itemId ~= 0 then
                mainFrame.slots[slotName]:SetItem(itemId)
            else mainFrame.slots[slotName]:RemoveItem() end
        end
    end)

    -- Apply saved look as morph
    btnApplyLook:HookScript("OnClick", function()
        if not IsMorpherReady() then
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: |cffff0000DLL not loaded!|r")
            return
        end
        local savedLooks = _G["TransmorpherSavedLooks"]
        local id = listFrame.buttons[listFrame:GetSelected()]:GetID()
        for index, slotName in pairs(slotOrder) do
            local itemId = savedLooks[id].items[index]
            if itemId ~= nil and itemId ~= 0 and slotToEquipSlotId[slotName] then
                    SendMorphCommand("ITEM:" .. slotToEquipSlotId[slotName] .. ":" .. itemId)
            end
        end
        SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Look applied as morph!")
    end)

    StaticPopupDialogs["Transmorpher_SAVE_DIALOG"] = {
        text = "|cffffd700Enter look name:",
        button1 = "Save", button2 = CLOSE,
        timeout = 0, whileDead = true, hasEditBox = true, preferredIndex = 3,
        OnAccept = function(self)
            local lookName = self.editBox:GetText()
            if lookName ~= "" then
                table.insert(_G["TransmorpherSavedLooks"], {["name"] = lookName, ["items"] = slots2ItemList()})
                listFrame:AddItem(lookName)
                SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Look '"..lookName.."' saved!")
            end
        end,
        OnShow = function(self) self.editBox:SetText("") end,
    }

    btnSaveAs:HookScript("OnClick", function() StaticPopup_Show("Transmorpher_SAVE_DIALOG") end)

    btnSave:HookScript("OnClick", function()
        if listFrame:GetSelected() then
            local id = listFrame.buttons[listFrame:GetSelected()]:GetID()
            _G["TransmorpherSavedLooks"][id].items = slots2ItemList()
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Look updated!")
        end
    end)

    btnRemove:HookScript("OnClick", function()
        if listFrame:GetSelected() then
            local id = listFrame.buttons[listFrame:GetSelected()]:GetID()
            table.remove(_G["TransmorpherSavedLooks"], id)
            listFrame:RemoveItem(listFrame:GetSelected())
            btnTryOn:Disable() btnRemove:Disable() btnSave:Disable() btnApplyLook:Disable()
        end
    end)
end

---------------- MORPH TAB (Race/Display ID) ----------------

local function UpdatePreviewModel()
    local f = CreateFrame("Frame")
    f.timer = 0.2
    f:SetScript("OnUpdate", function(self, elapsed)
        self.timer = self.timer - elapsed
        if self.timer <= 0 then
            if mainFrame and mainFrame.dressingRoom then
                mainFrame.dressingRoom:SetUnit("player")
            end
            self:Hide()
            self:SetScript("OnUpdate", nil)
        end
    end)
end

do
    local actualMorphTab = mainFrame.tabs.morph
    local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", actualMorphTab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)
    
    local morphTab = CreateFrame("Frame", "$parentContent", scrollFrame)
    morphTab:SetSize(actualMorphTab:GetWidth() - 30, 800) -- 800 is enough height for everything
    scrollFrame:SetScrollChild(morphTab)

    -- Update size dynamically just in case
    morphTab:SetScript("OnSizeChanged", function(self, width, height)
        self:SetWidth(width)
    end)

    local yOff = -5

    -- Title
    local titleText = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 10, yOff)
    titleText:SetText("|cff00ff00Character Morph|r")
    yOff = yOff - 22

    local subtitleText = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("TOPLEFT", 10, yOff)
    subtitleText:SetText("Change your character model. Client-side only.")
    yOff = yOff - 20

    -- Race display IDs: [race][gender] = displayId
    -- gender: 1 = neutral/unknown, 2 = male, 3 = female
    local raceDisplayIds = {
        ["Human"]      = { [2] = 49,    [3] = 50 },
        ["Orc"]        = { [2] = 51,    [3] = 52 },
        ["Dwarf"]      = { [2] = 53,    [3] = 54 },
        ["Night Elf"]  = { [2] = 55,    [3] = 56 },
        ["Undead"]     = { [2] = 57,    [3] = 58 },
        ["Tauren"]     = { [2] = 59,    [3] = 60 },
        ["Gnome"]      = { [2] = 1563,  [3] = 1564 },
        ["Troll"]      = { [2] = 1478,  [3] = 1479 },
        ["Blood Elf"]  = { [2] = 15476, [3] = 15475 },
        ["Draenei"]    = { [2] = 16125, [3] = 16126 },
    }
    local raceOrder = {"Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll", "Blood Elf", "Draenei"}
    local raceIcons = {
        ["Human"]      = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Orc"]        = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Dwarf"]      = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Night Elf"]  = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Undead"]     = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Tauren"]     = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Gnome"]      = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Troll"]      = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Blood Elf"]  = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
        ["Draenei"]    = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races",
    }

    -- Section: Race Morph
    local raceLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raceLabel:SetPoint("TOPLEFT", 10, yOff)
    raceLabel:SetText("|cffffd700Race Morph|r")
    yOff = yOff - 20

    local btnWidth = 120
    local btnHeight = 22
    local col = 0
    local startY = yOff

    for i, raceName in ipairs(raceOrder) do
        local ids = raceDisplayIds[raceName]
        local safeRaceName = raceName:gsub("%s+", "")

        -- Male button
        local btnM = CreateFrame("Button", "$parentRace"..safeRaceName.."M", morphTab, "UIPanelButtonTemplate2")
        btnM:SetSize(btnWidth, btnHeight)
        local xM = 10 + col * (btnWidth + 5)
        btnM:SetPoint("TOPLEFT", xM, yOff - (math.ceil(i/2) - 1) * (btnHeight + 3))
        btnM:SetText(raceName .. " M")
        btnM:SetScript("OnClick", function()
            if IsMorpherReady() then
                SendMorphCommand("MORPH:" .. ids[2])
                UpdatePreviewModel()
                SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Morphed to " .. raceName .. " Male (" .. ids[2] .. ")")
            end
            PlaySound("gsTitleOptionOK")
        end)
        btnM:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(raceName .. " Male")
            GameTooltip:AddLine("Display ID: " .. ids[2], 1, 1, 1)
            GameTooltip:Show()
        end)
        btnM:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Female button
        local btnF = CreateFrame("Button", "$parentRace"..safeRaceName.."F", morphTab, "UIPanelButtonTemplate2")
        btnF:SetSize(btnWidth, btnHeight)
        local xF = 10 + (col + 1) * (btnWidth + 5)
        btnF:SetPoint("TOPLEFT", xF, yOff - (math.ceil(i/2) - 1) * (btnHeight + 3))
        btnF:SetText(raceName .. " F")
        btnF:SetScript("OnClick", function()
            if IsMorpherReady() then
                SendMorphCommand("MORPH:" .. ids[3])
                UpdatePreviewModel()
                SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Morphed to " .. raceName .. " Female (" .. ids[3] .. ")")
            end
            PlaySound("gsTitleOptionOK")
        end)
        btnF:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(raceName .. " Female")
            GameTooltip:AddLine("Display ID: " .. ids[3], 1, 1, 1)
            GameTooltip:Show()
        end)
        btnF:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if i % 2 == 0 then col = 0 else col = 2 end
    end

    local raceSectionHeight = math.ceil(#raceOrder / 2) * (btnHeight + 3) + 10
    yOff = yOff - raceSectionHeight - 10

    -- Separator
    local sep1 = morphTab:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    sep1:SetTexCoord(0.81, 0.94, 0.5, 1)
    sep1:SetPoint("TOPLEFT", 10, yOff)
    sep1:SetPoint("RIGHT", -10, 0)
    sep1:SetHeight(8)
    sep1:SetVertexColor(0.3, 0.3, 0.3)
    yOff = yOff - 14

    -- Section: Custom Display ID
    local customLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customLabel:SetPoint("TOPLEFT", 10, yOff)
    customLabel:SetText("|cffffd700Custom Display ID|r")
    yOff = yOff - 20

    local customDesc = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customDesc:SetPoint("TOPLEFT", 10, yOff)
    customDesc:SetText("Enter any creature/NPC display ID to morph into:")
    yOff = yOff - 20

    local editBox = CreateFrame("EditBox", "$parentMorphIdInput", morphTab, "InputBoxTemplate")
    editBox:SetSize(140, 20)
    editBox:SetPoint("TOPLEFT", 15, yOff)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(6)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self)
        local id = tonumber(self:GetText())
        if id and id > 0 and IsMorpherReady() then
            SendMorphCommand("MORPH:" .. id)
            UpdatePreviewModel()
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Morphed to display ID " .. id)
        end
        self:ClearFocus()
    end)

    local btnApplyCustom = CreateFrame("Button", "$parentBtnApplyCustom", morphTab, "UIPanelButtonTemplate2")
    btnApplyCustom:SetSize(90, 22)
    btnApplyCustom:SetPoint("LEFT", editBox, "RIGHT", 10, 0)
    btnApplyCustom:SetText("|cff00ff00Apply|r")
    btnApplyCustom:SetScript("OnClick", function()
        local id = tonumber(editBox:GetText())
        if id and id > 0 and IsMorpherReady() then
            SendMorphCommand("MORPH:" .. id)
            UpdatePreviewModel()
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Morphed to display ID " .. id)
            PlaySound("gsTitleOptionOK")
        else
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Enter a valid display ID.")
        end
    end)

    yOff = yOff - 30

    -- Size (Scale) section
    local sizeLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", 10, yOff)
    sizeLabel:SetText("|cffffd700Character Size|r")
    yOff = yOff - 20

    local sizeEditBox = CreateFrame("EditBox", "$parentMorphSizeInput", morphTab, "InputBoxTemplate")
    sizeEditBox:SetSize(60, 20)
    sizeEditBox:SetPoint("TOPLEFT", 15, yOff)
    sizeEditBox:SetAutoFocus(false)
    sizeEditBox:SetNumeric(false) -- Allow decimals
    sizeEditBox:SetMaxLetters(4)
    sizeEditBox:SetText("1.0")
    sizeEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local btnApplySize = CreateFrame("Button", "$parentBtnApplySize", morphTab, "UIPanelButtonTemplate2")
    btnApplySize:SetSize(90, 22)
    btnApplySize:SetPoint("LEFT", sizeEditBox, "RIGHT", 10, 0)
    btnApplySize:SetText("|cff00ff00Apply Size|r")
    btnApplySize:SetScript("OnClick", function()
        local scale = tonumber(sizeEditBox:GetText())
        if scale and scale > 0.1 and scale < 10.0 and IsMorpherReady() then
            SendMorphCommand("SCALE:" .. scale)
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Scaled character to " .. scale)
            PlaySound("gsTitleOptionOK")
        else
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Enter a valid scale (0.1 to 10.0).")
        end
    end)
    
    yOff = yOff - 40

    -- Current display info
    local infoLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoLabel:SetPoint("TOPLEFT", 10, yOff)
    infoLabel:SetText("")
    yOff = yOff - 16

    -- Popular creature morphs section
    local creaturesLabel = morphTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    creaturesLabel:SetPoint("TOPLEFT", 10, yOff)
    creaturesLabel:SetText("|cffffd700Popular Creatures|r")
    yOff = yOff - 20

    local popularCreatures = {
        { name = "Lich King",     id = 22234 },
        { name = "Illidan",       id = 21135 },
        { name = "Sylvanas",      id = 28213 },
        { name = "Alexstrasza",   id = 28227 },
        
        { name = "Ragnaros",      id = 11121 },
        { name = "Deathwing",     id = 31969 },
        { name = "Malygos",       id = 25159 },
        { name = "Sindragosa",    id = 31053 },
        
        { name = "Kel'Thuzad",    id = 15945 },
        { name = "Yogg-Saron",    id = 28817 },
        { name = "Kael'thas",     id = 20023 },
        { name = "Lady Vashj",    id = 20748 },
        
        { name = "Nefarian",      id = 11380 },
        { name = "Onyxia",        id = 8570  },
        { name = "Arthas",        id = 24949 },
        { name = "Uther",         id = 16929 },
        
        { name = "Val'kyr",       id = 27157 },
        { name = "Murloc",        id = 390   },
        { name = "Leper Gnome",   id = 7568  },
        { name = "Ogre",          id = 4410  },
    }

    col = 0
    local creatureRow = 0
    for i, creature in ipairs(popularCreatures) do
        local btn = CreateFrame("Button", "$parentCreature"..i, morphTab, "UIPanelButtonTemplate2")
        btn:SetSize(btnWidth, btnHeight)
        btn:SetPoint("TOPLEFT", 10 + col * (btnWidth + 5), yOff - creatureRow * (btnHeight + 3))
        btn:SetText(creature.name)
        btn:SetScript("OnClick", function()
            if IsMorpherReady() then
                SendMorphCommand("MORPH:" .. creature.id)
                UpdatePreviewModel()
                SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Morphed to " .. creature.name .. " (" .. creature.id .. ")")
            end
            PlaySound("gsTitleOptionOK")
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(creature.name)
            GameTooltip:AddLine("Display ID: " .. creature.id, 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        col = col + 1
        if col >= 4 then col = 0; creatureRow = creatureRow + 1 end
    end

    local creatureSectionHeight = math.ceil(#popularCreatures / 4) * (btnHeight + 3) + 10
    yOff = yOff - creatureSectionHeight - 10

    -- Reset morph button (big, at bottom)
    local btnResetMorph = CreateFrame("Button", "$parentBtnResetModel", morphTab, "UIPanelButtonTemplate2")
    btnResetMorph:SetSize(200, 28)
    btnResetMorph:SetPoint("TOPLEFT", 10, yOff)
    btnResetMorph:SetText("|cffff6666Reset Character Model|r")
    btnResetMorph:SetScript("OnClick", function()
        if IsMorpherReady() then
            SendMorphCommand("RESET:ALL")
            mainFrame.dressingRoom:SetUnit("player")
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Character model reset!")
        end
        PlaySound("gsTitleOptionOK")
    end)

    -- Update display info on show
    morphTab:SetScript("OnShow", function()
        infoLabel:SetText("|cff888888Display info not available in stealth mode.|r")
    end)
end

---------------- SETTINGS TAB ----------------

do
    local settingsTab = mainFrame.tabs.settings
    local yOffset = -10

    local function createCheckbox(parent, label, settingKey, y)
        local cb = CreateFrame("CheckButton", "$parentCB_"..settingKey, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 10, y)
        _G[cb:GetName().."Text"]:SetText(label)
        _G[cb:GetName().."Text"]:SetFontObject("GameFontNormalSmall")
        cb:SetScript("OnClick", function(self)
            GetSettings()[settingKey] = self:GetChecked() == 1
            PlaySound("gsTitleOptionOK")
        end)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(GetSettings()[settingKey])
        end)
        return cb
    end

    createCheckbox(settingsTab, "Show shortcuts in tooltips", "showShortcutsInTooltip", yOffset)
    yOffset = yOffset - 28
    createCheckbox(settingsTab, "Hide hair on cloak preview", "hideHairOnCloakPreview", yOffset)
    yOffset = yOffset - 28
    createCheckbox(settingsTab, "Hide hair/beard on chest preview", "hideHairBeardOnChestPreview", yOffset)
    yOffset = yOffset - 28
    createCheckbox(settingsTab, "Announce appearance receiving", "announceAppearanceReceiving", yOffset)
    yOffset = yOffset - 28
    createCheckbox(settingsTab, "Persist morph across sessions", "saveMorphState", yOffset)

    -- DLL status indicator
    yOffset = yOffset - 40
    local statusText = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", 14, yOffset)

    settingsTab:SetScript("OnShow", function()
        if IsMorpherReady() then
            statusText:SetText("|cff00ff00Morpher DLL: LOADED|r")
        else
            statusText:SetText("|cffff0000Morpher DLL: NOT LOADED|r\nPlace dinput8.dll\nin your WoW folder.")
        end
    end)
end

---------------- RECEIVED APPEARANCES ----------------

do
    local receivedFrame = CreateFrame("Frame", "$parentReceived", mainFrame.tabs.appearances)
    receivedFrame:SetPoint("TOPRIGHT", -5, -30) receivedFrame:SetPoint("BOTTOM", 0, 30)
    receivedFrame:SetWidth(280)
    receivedFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    receivedFrame:SetBackdropColor(0, 0, 0, 1)

    local receivedLabel = receivedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    receivedLabel:SetPoint("CENTER", receivedFrame, "TOP", 0, 14)
    receivedLabel:SetText("Received Appearances")

    local scrollFrame2 = CreateFrame("ScrollFrame", "$parentScrollFrame2", receivedFrame, "UIPanelScrollFrameTemplate")
    scrollFrame2:SetPoint("TOPLEFT", 8, -8) scrollFrame2:SetPoint("BOTTOMLEFT", 8, 8)
    scrollFrame2:SetWidth(receivedFrame:GetWidth() - 12)

    local listFrame2 = ns.CreateListFrame("$parentReceivedLooks", nil, scrollFrame2)
    listFrame2:SetWidth(scrollFrame2:GetWidth())

    receivedFrame:SetScript("OnShow", function() scrollFrame2:SetScrollChild(listFrame2) end)

    -- Listen for appearances sent from other Transmorpher/DressMe users
    mainFrame:RegisterEvent("CHAT_MSG_ADDON")
    mainFrame:RegisterEvent("PLAYER_LOGIN")
    mainFrame:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
        if event == "PLAYER_LOGIN" then
            if TransmorpherCharacterState and GetSettings().saveMorphState then
                local f = CreateFrame("Frame")
                f.timer = 1.5
                f:SetScript("OnUpdate", function(self, elapsed)
                    self.timer = self.timer - elapsed
                    if self.timer <= 0 then
                        local cmdQueue = {}
                        if TransmorpherCharacterState.Scale then table.insert(cmdQueue, "SCALE:"..TransmorpherCharacterState.Scale) end
                        if TransmorpherCharacterState.Morph then table.insert(cmdQueue, "MORPH:"..TransmorpherCharacterState.Morph) end
                        if TransmorpherCharacterState.Items then
                            for slot, item in pairs(TransmorpherCharacterState.Items) do
                                table.insert(cmdQueue, "ITEM:"..slot..":"..item)
                            end
                        end
                        if #cmdQueue > 0 then
                            local fullCmd = table.concat(cmdQueue, "|")
                            if TRANSMORPHER_CMD == "" then
                                TRANSMORPHER_CMD = fullCmd
                            else
                                TRANSMORPHER_CMD = TRANSMORPHER_CMD .. "|" .. fullCmd
                            end
                        end
                        self:Hide()
                        self:SetScript("OnUpdate", nil)
                    end
                end)
            end
        elseif event == "CHAT_MSG_ADDON" and (prefix == addonMessagePrefix or prefix == "DressMe") then
            if GetSettings().announceAppearanceReceiving then
                SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: Received appearance from "..sender)
            end
            local items = {}
            for id in msg:gmatch("[^:]+") do
                table.insert(items, tonumber(id) or 0)
            end
            local timestamp = GetSettings().useServerTimeInReceivedAppearances and GetGameTime() or date("%H:%M")
            local lookName = sender .. " " .. timestamp
            listFrame2:AddItem(lookName)

            -- Store for try-on
            if not mainFrame.receivedLooks then mainFrame.receivedLooks = {} end
            table.insert(mainFrame.receivedLooks, {["name"] = lookName, ["items"] = items})
        end
    end)
end

---------------- SLASH COMMANDS ----------------

SLASH_Transmorpher1 = "/morph"
SLASH_Transmorpher2 = "/vm"
SLASH_Transmorpher3 = "/Transmorpher"

SlashCmdList["Transmorpher"] = function(msg)
    msg = msg:lower():trim()
    if msg == "reset" then
        if IsMorpherReady() then
            SendMorphCommand("RESET:ALL")
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: All morphs reset!")
        else
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: |cffff0000DLL not loaded!|r")
        end
    elseif msg == "status" then
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Transmorpher>|r: |cff00ff00Stealth Mode Active|r\nCommunicating via memory buffer.")
    else
        if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
    end
end

---------------- PAPERDOLL BUTTON ----------------

do
    -- Modern retail-style button on character frame
    local tmogBtn = CreateFrame("Button", "TransmorpherPaperDollButton", CharacterModelFrame)
    tmogBtn:SetSize(110, 28)
    tmogBtn:SetPoint("BOTTOMLEFT", 8, 32)
    
    -- Create custom backdrop for modern look
    tmogBtn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    tmogBtn:SetBackdropColor(0.1, 0.15, 0.25, 0.9)
    tmogBtn:SetBackdropBorderColor(0.3, 0.6, 1, 1)
    
    -- Icon for visual appeal
    local icon = tmogBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    -- Text with modern styling
    local btnText = tmogBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    btnText:SetText("|cff00d4ffTransmog|r")
    btnText:SetShadowColor(0, 0, 0, 1)
    btnText:SetShadowOffset(1, -1)
    tmogBtn:SetFontString(btnText)
    
    -- Glow effect on hover
    local glow = tmogBtn:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints()
    glow:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    glow:SetVertexColor(0.2, 0.4, 0.8, 0)
    glow:SetBlendMode("ADD")

    tmogBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 0.8, 1, 1)
        glow:SetVertexColor(0.2, 0.4, 0.8, 0.3)
        btnText:SetText("|cff66ddffTransmog|r")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cff00d4ffTransmogrifier|r", 1, 1, 1)
        GameTooltip:AddLine("Open the transmogrification interface", 0.7, 0.9, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Click|r to open", 0.5, 1, 0.5)
        GameTooltip:Show()
    end)
    
    tmogBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.6, 1, 1)
        glow:SetVertexColor(0.2, 0.4, 0.8, 0)
        btnText:SetText("|cff00d4ffTransmog|r")
        GameTooltip:Hide()
    end)
    
    tmogBtn:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(0.05, 0.1, 0.2, 0.9)
        icon:SetPoint("LEFT", 7, -1)
        btnText:SetPoint("LEFT", icon, "RIGHT", 5, -1)
    end)
    
    tmogBtn:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(0.1, 0.15, 0.25, 0.9)
        icon:SetPoint("LEFT", 6, 0)
        btnText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    end)

    tmogBtn:SetScript("OnClick", function()
        if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
        PlaySound("igCharacterInfoTab")
    end)
end

-- Print load message
DEFAULT_CHAT_FRAME:AddMessage("|cff00d4ff<Transmorpher>|r v1.0.0 loaded. Type |cff00ff00/morph|r to open or use the button on your character frame.")
