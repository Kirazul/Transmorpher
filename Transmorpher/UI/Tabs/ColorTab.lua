local addon, ns = ...

-- ============================================================
-- COLOR TAB  —  Damage Text
--   The numbers / words the client draws floating up off a unit in the 3D
--   world: your damage, crits, heals, MISS/DODGE/..., XP and honor. Recolored
--   in the DLL at the single creation chokepoint (WorldTextCreate), addressed by
--   the engine STYLE, so it works for your OWN hits too. (Blizzard's scrolling
--   combat-text panel is intentionally NOT touched.)
--
--   Each category gets a card (Forms-tab styling, with a glow when active):
--   pick a solid color, or switch it to a moving rainbow gradient. Plus global
--   rainbow-speed and size dials.
--
--   Settings are ACCOUNT-WIDE (ns.GetAccountSettings -> TransmorpherSettings) so
--   the look is identical on every character without reconfiguring.
--   World tint / lighting moods were removed; Weather & Sky moved to Misc >
--   Environment; Equipment recolor moved to Preview > Skin.
-- ============================================================

local mainFrame = ns.mainFrame
local root = mainFrame.tabs.color
if not root then return end

-- ----- account-wide settings + backend bridge ------------------
local function WT()
    return ns.GetAccountSettings().colorWorldText
end

local function Send(cmd)
    if ns.IsMorpherReady and ns.IsMorpherReady() then
        if ns.SendRawMorphCommand then ns.SendRawMorphCommand(cmd); return true
        elseif ns.SendMorphCommand then ns.SendMorphCommand(cmd); return true end
    end
    return false
end

-- category key -> { label, icon, engine style id, cvar, default {r,g,b} }
-- cvar = the Blizzard "Floating Combat Text" display toggle that makes this kind
-- of over-unit text exist at all; we turn it on when a category is enabled.
local WT_CATS = {
    { key = "damage",   label = "Damage",               style = 0, cvar = "CombatDamage",  icon = "Interface\\Icons\\Ability_Warrior_SavageBlow",   def = { 255,  80,  80 } },
    { key = "dmgcrit",  label = "Damage \226\128\148 Crit", style = 2, cvar = "CombatDamage",  icon = "Interface\\Icons\\Spell_Fire_FlameBolt",        def = { 255, 165,  40 } },
    { key = "heal",     label = "Healing",              style = 6, cvar = "CombatHealing", icon = "Interface\\Icons\\Spell_Holy_Heal",             def = {  80, 255,  90 } },
    { key = "healcrit", label = "Healing \226\128\148 Crit", style = 7, cvar = "CombatHealing", icon = "Interface\\Icons\\Spell_Holy_FlashHeal",        def = { 150, 255, 150 } },
    { key = "miss",     label = "Miss / Dodge / Parry", style = 3, cvar = "CombatDamage",  icon = "Interface\\Icons\\Spell_Magic_LesserInvisibilty", def = { 200, 200, 200 } },
    { key = "absorb",   label = "Absorb",               style = 1, cvar = "CombatDamage",  icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",  def = { 255, 230, 120 } },
    { key = "xp",       label = "XP Gained",            style = 4,                          icon = "Interface\\Icons\\INV_Misc_Book_11",            def = { 160, 130, 255 } },
    { key = "honor",    label = "Honor",                style = 5,                          icon = "Interface\\Icons\\INV_BannerPVP_02",            def = { 255, 120, 200 } },
}

local function WTRec(cat)
    local wt = WT()
    wt.cats[cat.key] = wt.cats[cat.key] or { enabled = false, mode = 0, r = cat.def[1], g = cat.def[2], b = cat.def[3] }
    return wt.cats[cat.key]
end

local function SendWorldTextCat(cat)
    local r = WTRec(cat)
    -- Make sure the engine is actually drawing this text, else there's nothing to color.
    if r.enabled and cat.cvar then pcall(SetCVar, cat.cvar, "1") end
    Send(("WTEXT:%d:%d:%d:%d:%d:%d"):format(cat.style, r.enabled and 1 or 0, r.mode or 0, r.r, r.g, r.b))
end

local function SendWorldTextGlobals()
    local wt = WT()
    Send("WTEXT_SPEED:" .. math.floor(((wt.speed or 25) / 100) * 1000 + 0.5))
    Send(("WTEXT_SIZE:%d:%d"):format(wt.size.enabled and 1 or 0, math.floor(((wt.size.pct or 100) / 100) * 1000 + 0.5)))
end

-- Re-push the whole Damage Text state to the DLL (login / DLL ready / sync).
function ns.WorldText_ApplyAll()
    for _, cat in ipairs(WT_CATS) do SendWorldTextCat(cat) end
    SendWorldTextGlobals()
end

-- ============================================================
-- Aggregate re-apply on DLL-ready (called from InitializeDLLSettings).
-- World tint/mood/brightness are gone, so we send their _OFF cleanups once to
-- wipe anything older builds may have persisted, then re-push the live features.
-- ============================================================
function ns.Color_ApplyAll()
    Send("MODELTINT_OFF"); Send("PTINT_OFF")
    Send("WORLDTINT_OFF"); Send("LIGHTPRESET_OFF")
    Send("WLIGHT_OFF");    Send("WBRIGHT_OFF")
    ns.WorldText_ApplyAll()
    if ns.Environment_ApplyAll then ns.Environment_ApplyAll() end   -- weather + sky (Misc)
    -- Skin persistence is mirrored after SendFullMorphState in DLLBridge. Applying it
    -- here runs before saved item descriptors are restored and can prune valid slots.
end

-- ----- shared UI helpers ----------------------------------------
local function GoldButton(parent, text, w)
    local b = ns.CreateGoldenButton and ns.CreateGoldenButton(nil, parent) or CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 100, 22); b:SetText(text)
    return b
end

local function OpenColorPicker(r, g, b, onChange)
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onChange(math.floor(nr * 255 + 0.5), math.floor(ng * 255 + 0.5), math.floor(nb * 255 + 0.5))
    end
    ColorPickerFrame.func = apply
    ColorPickerFrame.swatchFunc = apply
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame.cancelFunc = function(prev)
        if prev then onChange(math.floor(prev.r * 255 + 0.5), math.floor(prev.g * 255 + 0.5), math.floor(prev.b * 255 + 0.5)) end
    end
    ColorPickerFrame:SetColorRGB(r / 255, g / 255, b / 255)
    ColorPickerFrame:Hide(); ColorPickerFrame:Show()
end

-- ============================================================
-- Header / title
-- ============================================================
local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 12, -10); title:SetText("|cffF5C842Damage Text|r")
local subtitle = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
subtitle:SetText("|cff998866Recolor the floating numbers & words over a unit \226\128\148 works on your own hits. Client-side only.|r")

-- A single sub-tab pill (kept for visual consistency with the other tabs).
local subBtn = CreateFrame("Button", nil, root); subBtn:SetSize(120, 22)
subBtn:SetPoint("TOPLEFT", 12, -52)
do
    local bg = subBtn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(0.12, 0.10, 0.07, 1)
    local fs = subBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fs:SetPoint("CENTER"); fs:SetText("Damage Text")
    fs:SetTextColor(0.96, 0.78, 0.26, 1); subBtn:SetFontString(fs)
    local hl = subBtn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(0.96, 0.78, 0.26, 0.12); subBtn:SetHighlightTexture(hl)
end

-- The main panel that holds everything below the sub-tab pill.
local panel = CreateFrame("Frame", nil, root)
panel:SetPoint("TOPLEFT", 8, -80); panel:SetPoint("BOTTOMRIGHT", -8, 8)
panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
panel:SetBackdropColor(0.05, 0.055, 0.07, 0.93); panel:SetBackdropBorderColor(0.56, 0.47, 0.20, 0.7)

-- ---- quick-action header row (fixed) ----
local header = CreateFrame("Frame", nil, panel)
header:SetPoint("TOPLEFT", 8, -8); header:SetPoint("TOPRIGHT", -8, -8); header:SetHeight(34)
header:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
header:SetBackdropColor(0.08, 0.08, 0.08, 0.95); header:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)

local hdrTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
hdrTitle:SetPoint("LEFT", 12, 0); hdrTitle:SetTextColor(1.0, 0.84, 0.40); hdrTitle:SetText("Floating Combat Numbers")

local allOff  = GoldButton(header, "Turn Off", 76);    allOff:SetPoint("RIGHT", -10, 0)
local allRain = GoldButton(header, "Rainbow All", 92); allRain:SetPoint("RIGHT", allOff, "LEFT", -6, 0)
local allOn   = GoldButton(header, "Enable All", 84);  allOn:SetPoint("RIGHT", allRain, "LEFT", -6, 0)

-- ---- bottom controls (fixed): rainbow speed + size ----
local footer = CreateFrame("Frame", nil, panel)
footer:SetPoint("BOTTOMLEFT", 8, 8); footer:SetPoint("BOTTOMRIGHT", -8, 8); footer:SetHeight(78)
footer:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
footer:SetBackdropColor(0.06, 0.06, 0.06, 0.95); footer:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)

-- Rainbow speed
local spLbl = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
spLbl:SetPoint("TOPLEFT", 12, -10); spLbl:SetWidth(110); spLbl:SetJustifyH("LEFT"); spLbl:SetText("Rainbow speed")
local spSlider = CreateFrame("Slider", "TM_Color_WTSpeedSlider", footer, "OptionsSliderTemplate")
spSlider:SetWidth(210); spSlider:SetPoint("TOPLEFT", 126, -6)
spSlider:SetMinMaxValues(0, 100); spSlider:SetValueStep(5)
_G["TM_Color_WTSpeedSliderLow"]:SetText("Slow"); _G["TM_Color_WTSpeedSliderHigh"]:SetText("Fast")
_G["TM_Color_WTSpeedSliderText"]:SetText("")
local spVal = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); spVal:SetPoint("LEFT", spSlider, "RIGHT", 12, 0)
spSlider:SetScript("OnValueChanged", function(self)
    local v = math.floor(self:GetValue() + 0.5); WT().speed = v
    spVal:SetText(("|cffF5C842%d%%|r"):format(v)); SendWorldTextGlobals()
end)

-- Size
local szCb = CreateFrame("CheckButton", nil, footer, "ChatConfigCheckButtonTemplate")
szCb:SetSize(20, 20); szCb:SetPoint("TOPLEFT", 12, -42)
if ns.NormalizeCheckboxHitRect then ns.NormalizeCheckboxHitRect(szCb) end
local szLbl = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
szLbl:SetPoint("LEFT", szCb, "RIGHT", 4, 0); szLbl:SetWidth(82); szLbl:SetJustifyH("LEFT"); szLbl:SetText("Size")
local szSlider = CreateFrame("Slider", "TM_Color_WTSizeSlider", footer, "OptionsSliderTemplate")
szSlider:SetWidth(210); szSlider:SetPoint("TOPLEFT", 126, -38)
szSlider:SetMinMaxValues(30, 400); szSlider:SetValueStep(10)
_G["TM_Color_WTSizeSliderLow"]:SetText("Small"); _G["TM_Color_WTSizeSliderHigh"]:SetText("Huge")
_G["TM_Color_WTSizeSliderText"]:SetText("")
local szVal = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); szVal:SetPoint("LEFT", szSlider, "RIGHT", 12, 0)
local function pushSize()
    local sz = WT().size
    sz.enabled = szCb:GetChecked() and true or false
    sz.pct = math.floor(szSlider:GetValue() + 0.5)
    szVal:SetText(("|cffF5C842%d%%|r"):format(sz.pct)); SendWorldTextGlobals()
end
szCb:SetScript("OnClick", pushSize)
szSlider:SetScript("OnValueChanged", function() pushSize() end)

-- ---- card grid (scrolling, between header and footer) ----
local scroll = CreateFrame("ScrollFrame", "TM_Color_WTScroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -24, 6)
local content = CreateFrame("Frame", nil, scroll); content:SetSize(10, 10); scroll:SetScrollChild(content)

local cards = {}

local function RefreshCard(card)
    local c = WTRec(card.cat)
    card.swatch:SetBackdropColor(c.r / 255, c.g / 255, c.b / 255, 1)
    card.rainCb:SetChecked(c.mode == 1)
    card.enableCb:SetChecked(c.enabled)
    if not c.enabled then
        card.state:SetText("|cff707070Off|r")
        card.glow:Hide()
        if card.iconBorder then ns.HideMorphGlow(card.iconBorder) end
        card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
    elseif c.mode == 1 then
        card.state:SetText("|cffff6060R|cffffc040A|cff60ff60I|cff40c0ffN|cffc060ffB|cffff60c0OW|r")
        card.glow:Show()
        if card.iconBorder then ns.ShowMorphGlow(card.iconBorder, "gold") end
        card:SetBackdropBorderColor(0.78, 0.62, 0.22, 0.9)
    else
        card.state:SetText(("|cffBBBBBBSolid|r  |cff888888%d, %d, %d|r"):format(c.r, c.g, c.b))
        card.glow:Show()
        if card.iconBorder then ns.ShowMorphGlow(card.iconBorder, "gold") end
        card:SetBackdropBorderColor(0.78, 0.62, 0.22, 0.9)
    end
end

local function RefreshAll() for _, card in ipairs(cards) do RefreshCard(card) end end

local cols = 2
local gapX, gapY = 10, 10
local cardHeight = 84
local function Relayout()
    local w = scroll:GetWidth()
    if not w or w < 50 then return end
    cols = math.floor((w - 4 + gapX) / (230 + gapX))
    if cols < 2 then cols = 2 end
    if cols > 4 then cols = 4 end
    content:SetWidth(w)
    local cardWidth = math.floor((w - 4 - ((cols - 1) * gapX)) / cols)
    local row, col = 0, 0
    for _, card in ipairs(cards) do
        card:SetWidth(cardWidth)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 2 + col * (cardWidth + gapX), -(row * (cardHeight + gapY)))
        col = col + 1
        if col >= cols then col = 0; row = row + 1 end
    end
    local totalRows = row + (col > 0 and 1 or 0)
    content:SetHeight(math.max(scroll:GetHeight() or 1, totalRows * (cardHeight + gapY)))
end

local function BuildCard(cat)
    local card = CreateFrame("Frame", nil, content)
    card.cat = cat
    card:SetHeight(cardHeight)
    card:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    card:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)

    local glow = card:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", 1, -1); glow:SetPoint("BOTTOMRIGHT", -1, 1)
    glow:SetTexture("Interface\\Buttons\\WHITE8X8"); glow:SetVertexColor(0.50, 0.35, 0.08, 0.22); glow:Hide()
    card.glow = glow

    -- Icon + frame
    local iconBorder = CreateFrame("Frame", nil, card)
    iconBorder:SetPoint("TOPLEFT", 10, -10); iconBorder:SetSize(40, 40)
    iconBorder:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    iconBorder:SetBackdropColor(0.07, 0.07, 0.07, 1); iconBorder:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.9)
    local icon = iconBorder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(cat.icon); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.iconBorder = iconBorder

    local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -1)
    nameText:SetPoint("RIGHT", card, "RIGHT", -10, 0); nameText:SetJustifyH("LEFT"); nameText:SetWordWrap(false)
    nameText:SetTextColor(0.96, 0.90, 0.72); nameText:SetText(cat.label)

    local state = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    state:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4); state:SetJustifyH("LEFT"); state:SetWordWrap(false)
    card.state = state

    -- Color swatch (click = solid color + enable)
    local sw = CreateFrame("Button", nil, card); sw:SetSize(40, 16)
    sw:SetPoint("TOPLEFT", iconBorder, "BOTTOMLEFT", 0, -8)
    sw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    sw:SetBackdropBorderColor(0.8, 0.7, 0.3, 1)
    card.swatch = sw

    -- Enable checkbox
    local enableCb = CreateFrame("CheckButton", nil, card, "ChatConfigCheckButtonTemplate")
    enableCb:SetSize(20, 20); enableCb:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    if ns.NormalizeCheckboxHitRect then ns.NormalizeCheckboxHitRect(enableCb) end
    local enLbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enLbl:SetPoint("LEFT", enableCb, "RIGHT", 2, 0); enLbl:SetText("On")
    card.enableCb = enableCb

    -- Rainbow checkbox
    local rainCb = CreateFrame("CheckButton", nil, card, "ChatConfigCheckButtonTemplate")
    rainCb:SetSize(20, 20); rainCb:SetPoint("LEFT", enLbl, "RIGHT", 8, 0)
    if ns.NormalizeCheckboxHitRect then ns.NormalizeCheckboxHitRect(rainCb) end
    local rnLbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rnLbl:SetPoint("LEFT", rainCb, "RIGHT", 2, 0); rnLbl:SetText("Rainbow")
    card.rainCb = rainCb

    sw:SetScript("OnClick", function()
        local c = WTRec(cat)
        OpenColorPicker(c.r, c.g, c.b, function(nr, ng, nb)
            c.r, c.g, c.b = nr, ng, nb; c.enabled = true; c.mode = 0
            SendWorldTextCat(cat); RefreshCard(card)
        end)
    end)
    enableCb:SetScript("OnClick", function()
        WTRec(cat).enabled = enableCb:GetChecked() and true or false
        SendWorldTextCat(cat); RefreshCard(card)
    end)
    rainCb:SetScript("OnClick", function()
        local c = WTRec(cat); c.mode = rainCb:GetChecked() and 1 or 0
        if rainCb:GetChecked() then c.enabled = true end
        SendWorldTextCat(cat); RefreshCard(card)
    end)

    return card
end

for _, cat in ipairs(WT_CATS) do cards[#cards + 1] = BuildCard(cat) end
scroll:SetScript("OnSizeChanged", Relayout)

allOn:SetScript("OnClick", function()
    for _, cat in ipairs(WT_CATS) do WTRec(cat).enabled = true end
    ns.WorldText_ApplyAll(); RefreshAll()
end)
allRain:SetScript("OnClick", function()
    for _, cat in ipairs(WT_CATS) do local c = WTRec(cat); c.enabled = true; c.mode = 1 end
    ns.WorldText_ApplyAll(); RefreshAll()
end)
allOff:SetScript("OnClick", function()
    for _, cat in ipairs(WT_CATS) do local c = WTRec(cat); c.enabled = false; c.mode = 0 end
    Send("WTEXT_OFF"); ns.WorldText_ApplyAll(); RefreshAll()
end)

local function RefreshControls()
    local wt = WT()
    spSlider:SetValue(wt.speed or 25); spVal:SetText(("|cffF5C842%d%%|r"):format(wt.speed or 25))
    szCb:SetChecked(wt.size.enabled)
    szSlider:SetValue(wt.size.pct or 100); szVal:SetText(("|cffF5C842%d%%|r"):format(wt.size.pct or 100))
end

root:SetScript("OnShow", function()
    Relayout(); RefreshAll(); RefreshControls()
end)

-- Re-push when entering the world (the engine resets its style table on reload/zone).
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function() ns.WorldText_ApplyAll() end)

-- Defer the first layout one frame so the panel has its real width.
ns.RunAfter(0.05, function() Relayout(); RefreshAll(); RefreshControls() end)
