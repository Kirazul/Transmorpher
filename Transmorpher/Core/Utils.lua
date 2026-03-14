local addon, ns = ...

-- ============================================================
-- TRANSMORPHER UTILITIES
-- Shared UI factory functions and helpers
-- ============================================================

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ============================================================
-- HELPERS
-- ============================================================

function ns.ArrayHasValue(array, value)
    for i, v in ipairs(array) do
        if v == value then return true end
    end
    return false
end

function ns.GetSpellIcon(spellID)
    if spellID and spellID > 0 then
        local _, _, icon = GetSpellInfo(spellID)
        if icon then return icon end
    end
    return FALLBACK_ICON
end

function ns.GetCombatPetIcon(familyName)
    return ns.combatPetFamilyIcons[familyName] or "Interface\\Icons\\Ability_Hunter_BeastCall"
end

-- ============================================================
-- GOLDEN BUTTON FACTORY
-- Creates a styled golden button matching the WotLK theme
-- ============================================================
function ns.CreateGoldenButton(name, parent)
    local btn = CreateFrame("Button", name, parent)
    btn:SetNormalFontObject("GameFontNormal")
    btn:SetHighlightFontObject("GameFontHighlight")
    btn:SetDisabledFontObject("GameFontDisable")

    -- Normal texture (golden gradient)
    local normalTex = btn:CreateTexture(nil, "BACKGROUND")
    normalTex:SetAllPoints()
    normalTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    normalTex:SetGradientAlpha("VERTICAL", 0.25, 0.18, 0.08, 1.0, 0.18, 0.12, 0.05, 1.0)
    btn:SetNormalTexture(normalTex)

    -- Highlight texture (brighter golden)
    local highlightTex = btn:CreateTexture(nil, "HIGHLIGHT")
    highlightTex:SetAllPoints()
    highlightTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    highlightTex:SetGradientAlpha("VERTICAL", 0.35, 0.25, 0.12, 1.0, 0.28, 0.20, 0.08, 1.0)
    highlightTex:SetBlendMode("ADD")

    -- Pushed texture (darker)
    local pushedTex = btn:CreateTexture(nil, "ARTWORK")
    pushedTex:SetAllPoints()
    pushedTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    pushedTex:SetGradientAlpha("VERTICAL", 0.12, 0.08, 0.03, 1.0, 0.08, 0.05, 0.02, 1.0)
    btn:SetPushedTexture(pushedTex)

    -- Disabled texture (gray)
    local disabledTex = btn:CreateTexture(nil, "ARTWORK")
    disabledTex:SetAllPoints()
    disabledTex:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    disabledTex:SetVertexColor(0.15, 0.15, 0.15, 0.8)
    btn:SetDisabledTexture(disabledTex)

    -- Golden border
    btn:SetBackdrop(ns.Backdrops.button)
    btn:SetBackdropBorderColor(0.80, 0.65, 0.22, 1.0)

    -- Hover effect
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1.0, 0.82, 0.20, 1.0)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.80, 0.65, 0.22, 1.0)
    end)

    return btn
end

-- ============================================================
-- SEARCH BAR FACTORY
-- Creates a consistent search bar with icon, placeholder, and clear button
-- ============================================================
function ns.CreateSearchBar(parent, placeholder, width, height)
    width = width or 180
    height = height or 26

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.06, 0.05, 0.03, 0.9)
    frame:SetBackdropBorderColor(0.50, 0.42, 0.18, 0.8)

    -- Search icon
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 7, 0)
    icon:SetVertexColor(0.8, 0.75, 0.62)

    -- Edit box
    local editBox = CreateFrame("EditBox", nil, frame)
    editBox:SetPoint("TOPLEFT", 24, -3)
    editBox:SetPoint("BOTTOMRIGHT", -22, 3)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetTextColor(1, 1, 1)
    editBox:SetJustifyH("LEFT")

    -- Placeholder text
    local placeholderText = editBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholderText:SetPoint("LEFT", 2, 0)
    placeholderText:SetText(placeholder or "Search...")

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", -5, 0)
    clearBtn:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clearBtn:GetNormalTexture():SetAlpha(0.5)
    clearBtn:Hide()
    clearBtn:SetScript("OnClick", function()
        editBox:SetText("")
        editBox:ClearFocus()
    end)
    clearBtn:SetScript("OnEnter", function(self) self:GetNormalTexture():SetAlpha(1.0) end)
    clearBtn:SetScript("OnLeave", function(self) self:GetNormalTexture():SetAlpha(0.5) end)

    -- Edit box scripts
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function(self)
        placeholderText:Hide()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then placeholderText:Show() end
    end)
    editBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text == "" then
            placeholderText:Show()
            clearBtn:Hide()
        else
            placeholderText:Hide()
            clearBtn:Show()
        end
        if frame.onTextChanged then
            frame.onTextChanged(text)
        end
    end)

    frame.editBox = editBox
    frame.icon = icon
    frame.clearBtn = clearBtn
    frame.placeholder = placeholderText

    return frame
end

-- ============================================================
-- PANEL FACTORY
-- Creates a themed dark panel frame with golden border
-- ============================================================
function ns.CreatePanel(parent, backdrop)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetBackdrop(backdrop or ns.Backdrops.panel)
    panel:SetBackdropColor(unpack(ns.Colors.bgPanel))
    panel:SetBackdropBorderColor(unpack(ns.Colors.goldMuted))
    return panel
end

-- ============================================================
-- SECTION HEADER
-- Creates a section header label for settings groupings
-- ============================================================
function ns.CreateSectionHeader(parent, title, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetText(title)
    header:SetTextColor(unpack(ns.Colors.gold))
    header:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    if y then
        header:SetPoint("TOPLEFT", 16, y)
    end

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    line:SetVertexColor(unpack(ns.Colors.goldMuted))
    line:SetAlpha(0.6)

    header.line = line
    return header
end

-- ============================================================
-- CHECKBOX FACTORY
-- Creates a themed CheckButton for settings
-- ============================================================
function ns.CreateCheckbox(parent, label, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)

    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    text:SetTextColor(0.90, 0.85, 0.70)
    cb.label = text

    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 0.82, 0)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return cb
end

-- ============================================================
-- SCROLL FRAME FACTORY
-- Creates a scroll frame with standard scroll bar
-- ============================================================
function ns.CreateScrollFrame(parent, name)
    local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame.child = scrollChild
    return scrollFrame
end

-- NOTE: ShowMorphGlow/HideMorphGlow are defined in UI\GlowSystem.lua (animated version)
-- The basic glow stubs below were removed to avoid shadowing the advanced implementation.

-- ============================================================
-- TOOLTIP HELPERS
-- ============================================================

function ns.ShowItemTooltip(self, itemId)
    if itemId then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. itemId)
        GameTooltip:Show()
    end
end

function ns.HideTooltip()
    GameTooltip:Hide()
end
