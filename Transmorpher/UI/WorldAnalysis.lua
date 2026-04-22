local addon, ns = ...

local registeredCheckboxes = {}
local registeredSliderRefreshers = {}
local suppressUiCallbacks = false
local analysisScrollCounter = 0

local ANALYSIS_DEFAULTS = {
    worldRenderLiquidSurface = true,
    worldRenderLiquidParticles = true,
    worldRenderWireframe = false,
    worldRenderNormals = false,
    worldRenderTerrain = true,
    worldRenderTerrainCulling = true,
    worldRenderM2 = true,
    worldRenderM2WmoShadow = true,
    worldRenderWmo = true,
    worldRenderWmoLighting = true,
    worldRenderFootprints = true,
    worldRenderWmoTextures = true,
    worldRenderWmoPortals = false,
    worldRenderOccluders = false,
    worldRenderM2Fade = true,
    worldRenderGroundClutter = true,
    worldRenderCollision = false,
    worldRenderMountains = true,
    worldRenderSpecularLighting = true,
    worldRenderObjectShadow = true,
    worldRenderSmoothTextures = false,
    worldRenderSmoothTexturesBias = 1.25,
}

local ANALYSIS_SETTING_ALIASES = {
    worldRenderSmoothTextures = "espRenderSmoothTextures",
    worldRenderSmoothTexturesBias = "espRenderSmoothTexturesBias",
    worldRenderM2 = "espRenderM2",
    worldRenderTerrain = "espRenderTerrain",
    worldRenderTerrainCulling = "espRenderTerrainCulling",
    worldRenderM2WmoShadow = "espRenderM2WmoShadow",
    worldRenderWmo = "espRenderWmo",
    worldRenderWmoLighting = "espRenderWmoLighting",
    worldRenderFootprints = "espRenderFootprints",
    worldRenderWmoTextures = "espRenderWmoTextures",
    worldRenderWmoPortals = "espRenderWmoPortals",
    worldRenderOccluders = "espRenderOccluders",
    worldRenderM2Fade = "espRenderM2Fade",
    worldRenderGroundClutter = "espRenderGroundClutter",
    worldRenderCollision = "espRenderCollision",
    worldRenderLiquidSurface = "espRenderLiquidSurface",
    worldRenderLiquidParticles = "espRenderLiquidParticles",
    worldRenderMountains = "espRenderMountains",
    worldRenderSpecularLighting = "espRenderSpecularLighting",
    worldRenderObjectShadow = "espRenderObjectShadow",
    worldRenderWireframe = "espRenderWireframe",
    worldRenderNormals = "espRenderNormals",
}

local ANALYSIS_SYNC_KEYS = {
    { settingKey = "worldRenderSmoothTextures", cmd = "smoothtex", valueType = "bool" },
    { settingKey = "worldRenderSmoothTexturesBias", cmd = "smoothtexbias", valueType = "float" },
    { settingKey = "worldRenderM2", cmd = "renderm2" },
    { settingKey = "worldRenderTerrain", cmd = "renderterrain" },
    { settingKey = "worldRenderTerrainCulling", cmd = "terrainculling" },
    { settingKey = "worldRenderM2WmoShadow", cmd = "m2wmoshadow" },
    { settingKey = "worldRenderWmo", cmd = "renderwmo" },
    { settingKey = "worldRenderWmoLighting", cmd = "wmolighting" },
    { settingKey = "worldRenderFootprints", cmd = "footprints" },
    { settingKey = "worldRenderWmoTextures", cmd = "wmotextures" },
    { settingKey = "worldRenderWmoPortals", cmd = "wmoportals" },
    { settingKey = "worldRenderOccluders", cmd = "occluders" },
    { settingKey = "worldRenderM2Fade", cmd = "m2fade" },
    { settingKey = "worldRenderGroundClutter", cmd = "groundclutter" },
    { settingKey = "worldRenderCollision", cmd = "collision" },
    { settingKey = "worldRenderLiquidSurface", cmd = "liquidsurface" },
    { settingKey = "worldRenderLiquidParticles", cmd = "liquidparticles" },
    { settingKey = "worldRenderMountains", cmd = "mountains" },
    { settingKey = "worldRenderSpecularLighting", cmd = "specularlighting" },
    { settingKey = "worldRenderObjectShadow", cmd = "renderobjectshadow" },
    { settingKey = "worldRenderWireframe", cmd = "wireframe" },
    { settingKey = "worldRenderNormals", cmd = "normals" },
}

local function getSettings()
    return ns.GetSettings()
end

local function resolveAnalysisSettingKey(settingKey)
    return ANALYSIS_SETTING_ALIASES[settingKey] or settingKey
end

local function setAnalysisSetting(settingKey, value)
    local settings = getSettings()
    local resolvedKey = resolveAnalysisSettingKey(settingKey)
    settings[resolvedKey] = value
    if resolvedKey ~= settingKey then
        settings[settingKey] = value
    end
end

local function getAnalysisSetting(settingKey)
    local settings = getSettings()
    local resolvedKey = resolveAnalysisSettingKey(settingKey)
    local value = settings[resolvedKey]

    if value == nil and resolvedKey ~= settingKey then
        value = settings[settingKey]
        if value ~= nil then
            settings[resolvedKey] = value
        end
    end

    if value == nil then
        return ANALYSIS_DEFAULTS[settingKey]
    end
    return value
end

local function applyAnalysisDefaults()
    for _, entry in ipairs(ANALYSIS_SYNC_KEYS) do
        local defaultValue = ANALYSIS_DEFAULTS[entry.settingKey]
        if defaultValue ~= nil then
            setAnalysisSetting(entry.settingKey, defaultValue)
        end
    end
end

function ns.QueueWorldAnalysisSync()
    if not ns.IsMorpherReady or not ns.IsMorpherReady() then return end

    local payload = {}
    for _, entry in ipairs(ANALYSIS_SYNC_KEYS) do
        if entry.valueType == "float" then
            local value = tonumber(getAnalysisSetting(entry.settingKey)) or ANALYSIS_DEFAULTS[entry.settingKey] or 0
            table.insert(payload, entry.cmd .. "=" .. string.format("%.3f", value))
        else
            table.insert(payload, entry.cmd .. "=" .. (getAnalysisSetting(entry.settingKey) and "1" or "0"))
        end
    end

    TRANSMORPHER_ANALYSIS_CFG = table.concat(payload, ";")
end

local function refreshAnalysisControls()
    suppressUiCallbacks = true
    for _, cb in ipairs(registeredCheckboxes) do
        cb:SetChecked(getAnalysisSetting(cb.settingKey) and true or false)
    end
    for _, refresh in ipairs(registeredSliderRefreshers) do
        refresh()
    end
    suppressUiCallbacks = false
end

ns.RefreshWorldAnalysisControls = refreshAnalysisControls

function ns.ResetWorldAnalysisSettings()
    applyAnalysisDefaults()
    refreshAnalysisControls()
    ns.QueueWorldAnalysisSync()
end

local function applyCardStyle(card)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = true,
        tileSize = 8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
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
    card:SetPoint("TOPRIGHT", -18, y)
    card:SetHeight(height)
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

    return card
end

local function createCardButton(card, text, width, offsetX, onClick)
    local btn = ns.CreateGoldenButton(nil, card)
    btn:SetSize(width or 88, 22)
    btn:SetPoint("TOPRIGHT", card, "TOPRIGHT", offsetX or -12, -8)
    btn:SetText(text)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function createCheckboxRow(parent, label, settingKey, y, tooltip)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 12, y)
    row:SetPoint("TOPRIGHT", -12, y)
    row:SetHeight(34)

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    rowBg:SetAllPoints()
    rowBg:SetVertexColor(1, 1, 1, 0)

    local cb = CreateFrame("CheckButton", nil, row)
    cb:SetPoint("LEFT", 8, 0)
    cb:SetSize(22, 22)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb.settingKey = settingKey

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    text:SetText(label)
    text:SetTextColor(0.94, 0.88, 0.70)

    cb:SetScript("OnClick", function(self)
        if suppressUiCallbacks then return end
        setAnalysisSetting(settingKey, self:GetChecked() and true or false)
        ns.QueueWorldAnalysisSync()
        PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    end)

    if tooltip then
        row:EnableMouse(true)
        row:SetScript("OnEnter", function()
            rowBg:SetVertexColor(1, 1, 1, 0.04)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 0.82, 0)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            rowBg:SetVertexColor(1, 1, 1, 0)
            GameTooltip:Hide()
        end)
    end

    table.insert(registeredCheckboxes, cb)
    return cb
end

local function createScrollableContentFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", 0, -8)
    frame:SetPoint("BOTTOMRIGHT", -26, 10)
    frame:Hide()

    analysisScrollCounter = analysisScrollCounter + 1
    local scrollName = "TransmorpherWorldAnalysisScrollFrame" .. analysisScrollCounter
    local childName = "TransmorpherWorldAnalysisScrollChild" .. analysisScrollCounter

    local scroll = CreateFrame("ScrollFrame", scrollName, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    scroll:EnableMouseWheel(true)

    local content = CreateFrame("Frame", childName, scroll)
    content:SetHeight(1)
    content:SetWidth(math.max((frame:GetWidth() or 0) - 26, 1))
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(math.max((width or 0) - 28, 1))
    end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 32)))
    end)

    return frame, content
end

local function populateAnalysis(content)
    local y = -10
    local c0 = createCard(content, "Render Overrides", y, 150)
    createCardButton(c0, "Reset", 78, -12, function()
        ns.ResetWorldAnalysisSettings()
    end)
    createCheckboxRow(c0, "Smooth Textures", "worldRenderSmoothTextures", -42)

    local smoothBiasSlider = CreateFrame("Slider", "TransmorpherSmoothTextureBiasSlider", c0, "OptionsSliderTemplate")
    smoothBiasSlider:SetPoint("TOPLEFT", 18, -96)
    smoothBiasSlider:SetPoint("RIGHT", -20, 0)
    smoothBiasSlider:SetHeight(18)
    smoothBiasSlider:SetMinMaxValues(0, 10)
    smoothBiasSlider:SetValueStep(0.05)
    smoothBiasSlider:EnableMouseWheel(true)
    _G[smoothBiasSlider:GetName() .. "Low"]:SetText("0.00")
    _G[smoothBiasSlider:GetName() .. "High"]:SetText("10.00")

    local function updateSmoothBiasText(value)
        local text = _G[smoothBiasSlider:GetName() .. "Text"]
        text:SetText("Smoothness: " .. string.format("%.2f", value or 0))
        text:SetTextColor(1, 0.82, 0)
    end

    smoothBiasSlider:SetScript("OnValueChanged", function(self, value)
        local snapped = math.floor(((value or 0) * 20) + 0.5) / 20
        updateSmoothBiasText(snapped)
        if suppressUiCallbacks then return end
        setAnalysisSetting("worldRenderSmoothTexturesBias", snapped)
        ns.QueueWorldAnalysisSync()
    end)
    smoothBiasSlider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() - (delta * 0.10))
    end)

    table.insert(registeredSliderRefreshers, function()
        local value = tonumber(getAnalysisSetting("worldRenderSmoothTexturesBias")) or ANALYSIS_DEFAULTS.worldRenderSmoothTexturesBias
        smoothBiasSlider:SetValue(value)
        updateSmoothBiasText(value)
    end)

    y = y - 170
    local c1 = createCard(content, "Scene Visibility", y, 352)
    createCheckboxRow(c1, "M2 Models", "worldRenderM2", -42)
    createCheckboxRow(c1, "Terrain", "worldRenderTerrain", -68)
    createCheckboxRow(c1, "Terrain Culling", "worldRenderTerrainCulling", -94)
    createCheckboxRow(c1, "M2/WMO Shadow Link", "worldRenderM2WmoShadow", -120)
    createCheckboxRow(c1, "WMO Structures", "worldRenderWmo", -146)
    createCheckboxRow(c1, "Native WMO Lighting", "worldRenderWmoLighting", -172)
    createCheckboxRow(c1, "Footprints", "worldRenderFootprints", -198)
    createCheckboxRow(c1, "WMO Textures", "worldRenderWmoTextures", -224)
    createCheckboxRow(c1, "WMO Portals", "worldRenderWmoPortals", -250)
    createCheckboxRow(c1, "Occluders", "worldRenderOccluders", -276)
    createCheckboxRow(c1, "M2 Distance Fade", "worldRenderM2Fade", -302)

    y = y - 372
    local c2 = createCard(content, "Environment Flags", y, 240)
    createCheckboxRow(c2, "Ground Clutter", "worldRenderGroundClutter", -42)
    createCheckboxRow(c2, "Collision Geometry", "worldRenderCollision", -68)
    createCheckboxRow(c2, "Liquid Surface", "worldRenderLiquidSurface", -94)
    createCheckboxRow(c2, "Liquid Particles", "worldRenderLiquidParticles", -120)
    createCheckboxRow(c2, "Mountains/Horizon Geo", "worldRenderMountains", -146)
    createCheckboxRow(c2, "Specular Lighting", "worldRenderSpecularLighting", -172)
    createCheckboxRow(c2, "RenderObject Shadow", "worldRenderObjectShadow", -198)

    y = y - 260
    local c3 = createCard(content, "Debug Visualization", y, 110)
    createCheckboxRow(c3, "Wireframe", "worldRenderWireframe", -42)
    createCheckboxRow(c3, "Normals", "worldRenderNormals", -68)

    content:SetHeight(math.abs(y) + 130)
end

function ns.InitializeWorldAnalysisPanel(parent)
    if not parent or parent.transmorpherWorldAnalysisBuilt then return end

    local frame, content = createScrollableContentFrame(parent)
    populateAnalysis(content)
    frame:Show()

    parent.transmorpherWorldAnalysisBuilt = true
    parent.transmorpherWorldAnalysisFrame = frame

    refreshAnalysisControls()
end

local analysisReadyWatcher = CreateFrame("Frame")
analysisReadyWatcher.lastReady = false
analysisReadyWatcher:SetScript("OnUpdate", function(self)
    local ready = ns.IsMorpherReady and ns.IsMorpherReady()
    if ready and not self.lastReady then
        ns.QueueWorldAnalysisSync()
    end
    self.lastReady = ready and true or false
end)
