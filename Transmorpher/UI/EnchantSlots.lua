local addon, ns = ...

-- ============================================================
-- ENCHANT SLOTS — MH and OH enchant morphs above weapon slots
-- ============================================================

local mainFrame = ns.mainFrame

-- Enchant icon mapper
local ENCHANT_ICON_MAP = {
    { kw = "fiery",       icon = "Interface\\Icons\\Spell_Fire_FlameShock" },
    { kw = "fire",        icon = "Interface\\Icons\\Spell_Fire_FlameShock" },
    { kw = "sunfire",     icon = "Interface\\Icons\\Spell_Fire_SunKey" },
    { kw = "berserking",  icon = "Interface\\Icons\\Spell_Nature_Strength" },
    { kw = "mongoose",    icon = "Interface\\Icons\\Spell_Nature_Lightning" },
    { kw = "executioner", icon = "Interface\\Icons\\Ability_Warrior_Decisivestrike" },
    { kw = "icy",         icon = "Interface\\Icons\\Spell_Frost_FrostShock" },
    { kw = "frost",       icon = "Interface\\Icons\\Spell_Frost_FrostShock" },
    { kw = "deathfrost",  icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    { kw = "icebreaker",  icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    { kw = "lifestealing",icon = "Interface\\Icons\\Spell_Shadow_LifeDrain02" },
    { kw = "soulfrost",   icon = "Interface\\Icons\\Spell_Shadow_ChillTouch" },
    { kw = "unholy",      icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
    { kw = "shadow",      icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
    { kw = "fallen",      icon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
    { kw = "nerubian",    icon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
    { kw = "crusader",    icon = "Interface\\Icons\\Spell_Holy_HolyBolt" },
    { kw = "holy",        icon = "Interface\\Icons\\Spell_Holy_GreaterHeal" },
    { kw = "lifeward",    icon = "Interface\\Icons\\Spell_Holy_GreaterHeal" },
    { kw = "spellpower",  icon = "Interface\\Icons\\Spell_Holy_MindSooth" },
    { kw = "savagery",    icon = "Interface\\Icons\\Ability_Druid_Mangle2" },
    { kw = "agility",     icon = "Interface\\Icons\\Spell_Nature_Invisibilty" },
    { kw = "battlemaster",icon = "Interface\\Icons\\Spell_Holy_AshesToAshes" },
    { kw = "blood",       icon = "Interface\\Icons\\Spell_DeathKnight_BloodPresence" },
    { kw = "rune",        icon = "Interface\\Icons\\Spell_DeathKnight_FrostPresence" },
    { kw = "razorice",    icon = "Interface\\Icons\\Spell_Frost_FrostArmor" },
    { kw = "cinderglacier",icon = "Interface\\Icons\\Spell_Frost_ChainsOfIce" },
    { kw = "lichbane",    icon = "Interface\\Icons\\Spell_Shadow_SoulLeech_3" },
    { kw = "stoneskin",   icon = "Interface\\Icons\\Spell_DeathKnight_AntiMagicZone" },
    { kw = "swordbreaking",icon = "Interface\\Icons\\INV_Sword_62" },
    { kw = "spellshattering",icon = "Interface\\Icons\\Spell_Arcane_MassDispel" },
    { kw = "titanium",    icon = "Interface\\Icons\\INV_Ingot_Titanium" },
    { kw = "giant",       icon = "Interface\\Icons\\Ability_Warrior_Cleave" },
    { kw = "massacre",    icon = "Interface\\Icons\\Ability_Warrior_Bladestorm" },
    { kw = "demon",       icon = "Interface\\Icons\\Spell_Shadow_Metamorphosis" },
    { kw = "adamantite",  icon = "Interface\\Icons\\INV_Ingot_Adamantite" },
    { kw = "chain",       icon = "Interface\\Icons\\INV_Belt_13" },
    { kw = "plating",     icon = "Interface\\Icons\\INV_Shield_35" },
}
local ENCHANT_ICON_DEFAULT = "Interface\\Icons\\INV_Enchant_FormulaEpic_01"

local function GetEnchantIcon(enchantName)
    if not enchantName then return ENCHANT_ICON_DEFAULT end
    local lower = enchantName:lower()
    for _, entry in ipairs(ENCHANT_ICON_MAP) do
        if lower:find(entry.kw, 1, true) then return entry.icon end
    end
    return ENCHANT_ICON_DEFAULT
end
ns.GetEnchantIcon = GetEnchantIcon

mainFrame.enchantSlots = {}

local enchantSlotInfo = {
    ["Enchant MH"] = { anchor = "Main Hand", cmd = "ENCHANT_MH" },
    ["Enchant OH"] = { anchor = "Off-hand",  cmd = "ENCHANT_OH" },
}

for _, eName in ipairs(ns.enchantSlotNames) do
    local info = enchantSlotInfo[eName]
    local eSlot = CreateFrame("Button", "$parentEnchant"..eName:gsub(" ",""), mainFrame, "ItemButtonTemplate")
    eSlot:SetSize(28, 28)
    eSlot:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 2)
    eSlot:SetPoint("BOTTOM", mainFrame.slots[info.anchor], "TOP", 0, 2)
    eSlot.slotName = eName
    eSlot.cmd = info.cmd
    eSlot.enchantId = nil
    eSlot.enchantName = nil
    eSlot.textures = {}

    local emptyTex = eSlot:CreateTexture(nil, "BACKGROUND")
    emptyTex:SetAllPoints()
    emptyTex:SetTexture("Interface\\Paperdoll\\ui-paperdoll-slot-mainhand")
    emptyTex:SetVertexColor(0.6, 0.4, 1.0, 0.5)
    eSlot.textures.empty = emptyTex

    local enchIcon = eSlot:CreateTexture(nil, "ARTWORK")
    enchIcon:SetPoint("TOPLEFT", 2, -2); enchIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    enchIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92); enchIcon:Hide()
    eSlot.textures.enchantIcon = enchIcon

    local labelTex = eSlot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelTex:SetPoint("TOP", eSlot, "BOTTOM", 0, -1)
    labelTex:SetText("|cffC0A060E|r"); labelTex:SetFont("Fonts\\FRIZQT__.TTF", 8)
    eSlot.textures.label = labelTex

    eSlot.SetEnchant = function(self, enchantId, enchantName)
        self.enchantId = enchantId; self.enchantName = enchantName
        self.textures.enchantIcon:SetTexture(GetEnchantIcon(enchantName))
        self.textures.enchantIcon:Show(); self.textures.empty:Hide()
        ns.ShowMorphGlow(self, "blue") -- Blue for previewing enchants
    end

    eSlot.RemoveEnchant = function(self)
        self.enchantId = nil; self.enchantName = nil
        self.textures.enchantIcon:Hide()
        self.textures.empty:SetVertexColor(0.6, 0.4, 1.0, 0.5); self.textures.empty:Show()
        ns.HideMorphGlow(self)
    end

    eSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    eSlot:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if IsAltKeyDown() and self.enchantId then
                if ns.IsMorpherReady() then
                    ns.SendMorphCommand(info.cmd..":"..self.enchantId)
                    self.isMorphed = true
                    SELECTED_CHAT_FRAME:AddMessage("|cffF5C842<Transmorpher>|r: Enchant applied to "..eName.."!")
                    ns.ShowMorphGlow(self, "orange")
                    if ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05) end
                end
                PlaySound("gsTitleOptionOK"); return
            end
            if mainFrame.selectedSlot then mainFrame.selectedSlot:UnlockHighlight() end
            for _, es in pairs(mainFrame.enchantSlots) do es:UnlockHighlight() end
            mainFrame.selectedSlot = nil
            mainFrame.selectedEnchantSlot = self
            self:LockHighlight()
            ns.tab_OnClick(mainFrame.buttons["tab1"])
            if mainFrame.tabs.preview.ShowSubTab then
                mainFrame.tabs.preview.ShowSubTab(1)
            end
            if mainFrame.tabs.preview.itemsSubTab and mainFrame.tabs.preview.itemsSubTab.UpdateEnchantMode then
                mainFrame.tabs.preview.itemsSubTab:UpdateEnchantMode(eName)
            end
            PlaySound("gsTitleOptionOK")
        elseif button == "RightButton" then
            local didChange = false
            if self.isMorphed then
                if self.cmd == "ENCHANT_MH" then
                    ns.SendMorphCommand("ENCHANT_RESET_MH")
                    didChange = true
                    local setKey = ns.GetWeaponSetKey()
                    if TransmorpherCharacterState.WeaponSets and TransmorpherCharacterState.WeaponSets[setKey] then
                        TransmorpherCharacterState.WeaponSets[setKey].EnchantMH = nil
                    end
                elseif self.cmd == "ENCHANT_OH" then
                    ns.SendMorphCommand("ENCHANT_RESET_OH")
                    didChange = true
                    local setKey = ns.GetWeaponSetKey()
                    if TransmorpherCharacterState.WeaponSets and TransmorpherCharacterState.WeaponSets[setKey] then
                        TransmorpherCharacterState.WeaponSets[setKey].EnchantOH = nil
                    end
                end
            end
            self.isMorphed = false; self:RemoveEnchant(); ns.HideMorphGlow(self)
            if didChange and ns.ScheduleDressingRoomSync then ns.ScheduleDressingRoomSync(0.05) end
            PlaySound("gsTitleOptionOK")
        end
    end)

    eSlot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.enchantId then
            GameTooltip:AddLine("|cffF5C842"..(self.enchantName or "Enchant").."|r")
            GameTooltip:AddLine("Enchant ID: "..self.enchantId, 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Alt+Click to apply enchant morph", 0.5, 0.8, 0.5)
            GameTooltip:AddLine("Right-click to remove", 0.8, 0.5, 0.5)
        else
            GameTooltip:AddLine(eName)
            GameTooltip:AddLine("Click to browse enchant effects", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    eSlot:SetScript("OnLeave", function() GameTooltip:Hide() end)

    mainFrame.enchantSlots[eName] = eSlot
end
