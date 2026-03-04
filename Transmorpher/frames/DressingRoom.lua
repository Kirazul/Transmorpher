
local addon, ns = ...

local defaultWidth = 350
local defaultHeight = 430

-- SetLight(enabled, omni, dirX, dirY, dirZ, ambIntensity, ambR, ambG, ambB, dirIntensity, dirR, dirG, dirB)
local defaultLight = {1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64}

local xStep = 0.2 -- per pixel
local zStep = 0.003 -- per pixel
local facingStep = math.rad(0.75) -- per pixel

local sex = {male = 2, female = 3}
sex[sex.male] = "male"
sex[sex.female] = "female"
local male, female = 2, 3

local modelX = { -- male = 2, female = 3
    min = {
        -- The Alliance
        Dwarf =     {male = -0.75, female = -0.75},
        Draenei =   {male = -0.75, female = -0.75},
        Gnome =     {male = -0.75, female = -0.75},
        Human =     {male = -0.75, female = -0.75},
        NightElf =  {male = -0.75, female = -0.75},
        -- The Horde
        BloodElf =  {male = -0.75, female = -0.75},
        Orc =       {male = -0.75, female = -0.75},
        Scourge =   {male = -0.75, female = -0.75},
        Tauren =    {male = -0.75, female = -0.75},
        Troll =     {male = -0.75, female = -0.75},
    },
    max = {
        -- The Alliance
        Dwarf =     {male = 2.6, female = 1.55},
        Draenei =   {male = 3.2, female = 3.0},
        Gnome =     {male = 1.44, female = 1.1},
        Human =     {male = 2.10, female = 1.9},
        NightElf =  {male = 3.3, female = 3.2},
        -- The Horde
        BloodElf =  {male = 2.9, female = 2.2},
        Orc =       {male = 2.2, female = 2.35},
        Scourge =   {male = 2.0, female = 3.0},
        Tauren =    {male = 2.90, female = 2.4},
        Troll =     {male = 3.0, female = 3.0},
    },
}

local modelZ = {
    min = {
        -- The Alliance
        Dwarf =     {male = -0.80, female = -0.60},
        Draenei =   {male = -1.15, female = -0.97},
        Gnome =     {male = -0.30, female = -0.32},
        Human =     {male = -1.05, female = -1.76},
        NightElf =  {male = -1.05, female = -0.87},
        -- The Horde
        BloodElf =  {male = -1.00, female = -0.75},
        Orc =       {male = -0.75, female = -0.75},
        Scourge =   {male = -0.80, female = -0.67},
        Tauren =    {male = -0.80, female = -0.50},
        Troll =     {male = -0.75, female = -0.75},
    },
    max = {
        -- The Alliance
        Dwarf =     {male = 0.52, female = 0.75},
        Draenei =   {male = 1.15, female = 0.92},
        Gnome =     {male = 0.48, female = 0.47},
        Human =     {male = 0.78, female = 0.77},
        NightElf =  {male = 0.96, female = 0.96},
        -- The Horde
        BloodElf =  {male = 0.75, female = 0.80},
        Orc =       {male = 0.95, female = 0.9},
        Scourge =   {male = 0.75, female = 0.85},
        Tauren =    {male = 0.90, female = 1.35},
        Troll =     {male = 1.25, female = 1.25},
    },
}


function ns.CreateDressingRoom(name, parent)
    local frame = CreateFrame("Frame", name, parent)
    frame:EnableMouseWheel(true)
    frame:SetSize(defaultWidth, defaultHeight)
    frame:SetMinResize(defaultWidth, defaultHeight)
    frame:SetMaxResize(defaultWidth, defaultHeight)

    local unit = "player"
    local _, unitRaceFileName = UnitRace(unit)
    local unitSex = UnitSex(unit)

    local model = CreateFrame("DressUpModel", nil, frame)
    model:SetAllPoints()
    model:SetUnit("player")

    local dragDummy = CreateFrame("Frame", nil, frame)
    dragDummy:SetPoint("TOPLEFT", 24, -24)
    dragDummy:SetPoint("BOTTOMRIGHT", -24, 24)
    dragDummy:EnableMouse(true)
    dragDummy:SetMovable(true)

    dragDummy:SetScript("OnMouseDown", function(self, button)
        self:StartMoving()
        local cursorX, cursorY = GetCursorPosition()
        if button == "LeftButton" then
            self:SetScript("OnUpdate", function(self, elapsed)
                local newX, newY = GetCursorPosition()
                local deltaX = newX - cursorX
                model:SetFacing(model:GetFacing() + deltaX * facingStep)
                cursorX, cursorY = newX, newY
            end)
        elseif button == "RightButton" and IsAltKeyDown() then
            self:SetScript("OnUpdate", function(self, elapsed)
                local newX, newY = GetCursorPosition()
                frame:GetScript("OnMouseWheel")(frame, (newY - cursorY) * 0.05)
                cursorX, cursorY = newX, newY
            end)
        elseif button == "RightButton" then
            self:SetScript("OnUpdate", function(self, elapsed)
                local newX, newY = GetCursorPosition()
                local deltaY = newY - cursorY
                local x, y, z = model:GetPosition()
                local zOffset = zStep * deltaY
                z = z + zOffset
                local max, min = modelZ.max[unitRaceFileName][sex[unitSex]], modelZ.min[unitRaceFileName][sex[unitSex]]
                z = z > max and max or z
                z = z < min and min or z
                model:SetPosition(x, y, z)
                cursorX, cursorY = newX, newY
            end)
        end
    end)

    dragDummy:SetScript("OnMouseUp", function(self) 
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -24)
        self:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 24)
    end)

    dragDummy:SetScript("OnHide", dragDummy:GetScript("OnMouseUp"))

    local dbgFrame = CreateFrame("Frame", nil, model)
    dbgFrame:Hide()
    dbgFrame:EnableMouse(false)
    dbgFrame:EnableMouseWheel(false)
    dbgFrame:SetAllPoints()

    local dbgInfo = dbgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dbgInfo:SetAllPoints()
    dbgInfo:SetJustifyH("LEFT")
    dbgInfo:SetJustifyV("TOP")

    function frame:ShowDebugInfo()
        dbgFrame:Show()
        dbgFrame:SetScript("OnUpdate", function(self, elapsed)
            local facing = model:GetFacing()
            local x, y, z = model:GetPosition()
            dbgInfo:SetFormattedText("Facing = %f\nX = %f\nZ = %f", facing, x, z)
        end)
    end

    function frame:HideDebugInfo() dbgFrame:Hide() end
    function frame:IsDebugInfoShown() return dbgFrame:IsShown() end

    function frame:Reset()
        local x, y, z = model:GetPosition()
        local facing = model:GetFacing()
        model:SetPosition(0, 0, 0)
        model:SetFacing(0)
        model:ClearModel()
        model:SetUnit("player")

        unit = "player"
        _, unitRaceFileName = UnitRace(unit)
        unitSex = UnitSex(unit)

        local minX = modelX.min[unitRaceFileName][sex[unitSex]]
        local maxX = modelX.max[unitRaceFileName][sex[unitSex]]
        local minZ = modelZ.min[unitRaceFileName][sex[unitSex]]
        local maxZ = modelZ.max[unitRaceFileName][sex[unitSex]]

        x = x < minX and minX or x > maxX and maxX or x
        z = z < minZ and minZ or z > maxZ and maxZ or z

        model:SetPosition(x, y, z)
        model:SetFacing(facing)
        model:SetLight(unpack(defaultLight))
    end

    function frame:SetUnit(newUnit)
        if UnitIsPlayer(newUnit) and CheckInteractDistance(newUnit, 1) then
            local x, y, z = model:GetPosition()    
            local facing = model:GetFacing()
            model:SetPosition(0, 0, 0)
            model:SetFacing(0)
            model:ClearModel()
            model:SetUnit(newUnit)
            unit = newUnit
            _, unitRaceFileName = UnitRace(unit)
            unitSex = UnitSex(unit)
            local minX = modelX.min[unitRaceFileName][sex[unitSex]]
            local maxX = modelX.max[unitRaceFileName][sex[unitSex]]
            local minZ = modelZ.min[unitRaceFileName][sex[unitSex]]
            local maxZ = modelZ.max[unitRaceFileName][sex[unitSex]]

            x = x < minX and minX or x > maxX and maxX or x
            z = z < minZ and minZ or z > maxZ and maxZ or z

            model:SetPosition(x, y, z)
            model:SetFacing(facing)
        end
    end

    function frame:ClearModel(...) model:ClearModel(...) end
    function frame:TryOn(...) model:TryOn(...) end
    function frame:Undress() model:Undress() end
    function frame:GetPosition(...) return model:GetPosition(...) end
    function frame:SetPosition(...) model:SetPosition(...) end
    function frame:GetFacing(...) return model:GetFacing(...) end
    function frame:SetFacing(...) model:SetFacing(...) end
    function frame:SetSequence(...) model:SetSequence(...) end
    function frame:SetLight(...) model:SetLight(...) end
    function frame:GetLight(...) return model:GetLight(...) end
    function frame:SetModelAlpha(...) model:SetAlpha(...) end
    function frame:GetModelAlpha(...) return model:GetAlpha(...) end
    function frame:OnUpdateModel(...) model:SetScript("OnUpdateModel", ...) end
    function frame:EnableDragRotation(enable) 
        if enable then dragDummy:Show() else dragDummy:Hide() end
    end

    local originSetBackdrop = frame.SetBackdrop
    function frame:SetBackdrop(backdrop)
        originSetBackdrop(frame, backdrop)
        model:SetPoint("TOPLEFT", backdrop.insets.left * 2, -backdrop.insets.top * 2)
        model:SetPoint("BOTTOMRIGHT", -backdrop.insets.right * 2, backdrop.insets.bottom * 2)
    end

    frame:SetScript("OnMouseWheel", function (self, delta)
        local x, y, z = model:GetPosition()
        x = x + delta * xStep
        local max, min = modelX.max[unitRaceFileName][sex[unitSex]], modelX.min[unitRaceFileName][sex[unitSex]]
        x = x > max and max or x
        x = x < min and min or x
        model:SetPosition(x, y ,z)
    end)

    for _, child in pairs({frame:GetChildren()}) do
        child:SetFrameLevel(frame:GetFrameLevel())
    end

    return frame
end
