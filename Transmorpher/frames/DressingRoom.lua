
local addon, ns = ...

local defaultWidth = 350
local defaultHeight = 430

-- SetLight(enabled, omni, dirX, dirY, dirZ, ambIntensity, ambR, ambG, ambB, dirIntensity, dirR, dirG, dirB)
local defaultLight = {1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64}

local xStep = 0.2 -- per pixel
local zStep = 0.003 -- per pixel
local facingStep = math.rad(0.75) -- per pixel

-- Kept in sync with StealthMorpher/src/Utils.cpp preview sentinels.
local PV_TRYON_BASE = 0x10000000
local PV_TRYON_SLOT_BASE = 0x18000000
local PV_TRYON_SLOT_STRIDE = 0x00100000
local PV_UNDRESS = 0x1FFFFFFF

local function GetForcedWeaponSlotId(slotName)
    if slotName == ns.mainHandSlot or slotName == "Main Hand" then return 16 end
    if slotName == ns.offHandSlot or slotName == "Off-hand" then return 17 end
    if slotName == ns.rangedSlot or slotName == "Ranged" then return 18 end
    return nil
end

local function CanUsePreviewSentinel(model)
    return model and model.SetCreature and ns.IsMorpherReady and ns.IsMorpherReady()
end

function ns.TryOnPreviewItem(model, itemId, slotName)
    itemId = tonumber(itemId)
    if not model or not itemId or itemId <= 0 then return false end
    local targetModel = model
    if targetModel.GetModel and targetModel.liveUnitModel ~= nil then targetModel = targetModel:GetModel() end

    local forcedSlot = GetForcedWeaponSlotId(slotName)
    if forcedSlot and CanUsePreviewSentinel(targetModel) and itemId < PV_TRYON_SLOT_STRIDE then
        targetModel:SetCreature(PV_TRYON_SLOT_BASE + forcedSlot * PV_TRYON_SLOT_STRIDE + itemId)
        return true
    end

    if targetModel and targetModel.TryOn then
        targetModel:TryOn(itemId)
        return true
    end

    if CanUsePreviewSentinel(targetModel) then
        targetModel:SetCreature(PV_TRYON_BASE + itemId)
        return true
    end
    return false
end

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


-- ============================================================
-- DRESSING ROOM
-- Default path matches DressMe: a plain DressUpModel based on player, with TryOn
-- and Undress applied directly. liveUnitModel remains only for callers that
-- explicitly request it; Transmorpher's main Character Preview does not.
-- ============================================================
function ns.CreateDressingRoom(name, parent, opts)
    local frame = CreateFrame("Frame", name, parent)
    frame:EnableMouseWheel(true)
    frame:SetSize(defaultWidth, defaultHeight)
    frame:SetMinResize(defaultWidth, defaultHeight)
    frame:SetMaxResize(defaultWidth, defaultHeight)
    opts = opts or {}
    local liveUnitModel = opts.liveUnitModel and true or false

    local unit = "player"
    local _, unitRaceFileName = UnitRace(unit)
    local unitSex = UnitSex(unit)

    local model
    if liveUnitModel then
        local ok, liveModel = pcall(CreateFrame, "PlayerModel", nil, frame)
        if ok and liveModel then
            model = liveModel
        else
            liveUnitModel = false
        end
    end
    if not model then
        model = CreateFrame("DressUpModel", nil, frame)
    end
    frame.liveUnitModel = liveUnitModel
    model:SetAllPoints()
    model:SetUnit("player")

    function frame:GetModel()
        return model
    end

    function frame:IsLiveUnitModel()
        return self.liveUnitModel and true or false
    end

    -- Re-stamp the live model so it matches the real character right now.
    -- While a FAKED preview is active (item try-on / undress driven purely client-side),
    -- re-stamping would wipe it, so we re-apply the preview instead — this keeps a tried-on
    -- item visible across the equipment/model events that fire while browsing.
    function frame:RefreshLiveUnit()
        if not self.liveUnitModel then return end
        if self.previewActive then
            if self.previewUndressed then self:PreviewUndressFaked() else self:PreviewApplyItems() end
            return
        end
        model:ClearModel()
        model:SetUnit(unit or "player")
    end

    -- The faked preview only works when the DLL is loaded (it provides the SetCreature hook).
    -- Without it we must NOT poke SetCreature with a sentinel (the real SetCreature would try
    -- to load a bogus creature), so we simply don't preview.
    function frame:CanFakePreview()
        return self.liveUnitModel and ns.IsMorpherReady and ns.IsMorpherReady() and true or false
    end

    -- Faked, client-side ONLY: show the currently-selected slot items on the live model with
    -- no server morph and no sync. Base = the real character (SetUnit player); the chosen
    -- items are tried on top via the SetCreature-sentinel hook. Weapons last (their attach
    -- order matters), mirroring ns.DressPreviewModel. The real morph only happens on Apply All.
    function frame:PreviewApplyItems()
        if not self:CanFakePreview() then return end   -- DLL absent: no-op (model stays live)
        self.previewActive = true
        self.previewUndressed = false
        model:SetUnit("player")
        local items = ns.BuildPreviewSlotItems and ns.BuildPreviewSlotItems() or {}
        local mainHand, offHand, ranged
        for _, slotName in ipairs(ns.slotOrder or {}) do
            local id = items[slotName]
            if id and id > 0 then
                if slotName == ns.mainHandSlot or slotName == "Main Hand" then mainHand = id
                elseif slotName == ns.offHandSlot or slotName == "Off-hand" then offHand = id
                elseif slotName == ns.rangedSlot or slotName == "Ranged" then ranged = id
                else ns.TryOnPreviewItem(model, id, slotName) end
            end
        end
        if offHand then ns.TryOnPreviewItem(model, offHand, ns.offHandSlot or "Off-hand") end
        if mainHand then ns.TryOnPreviewItem(model, mainHand, ns.mainHandSlot or "Main Hand") end
        if ranged and not mainHand and not offHand then ns.TryOnPreviewItem(model, ranged, ns.rangedSlot or "Ranged") end
    end

    -- Faked undress of the live model (the real character keeps its gear).
    function frame:PreviewUndressFaked()
        if not self.liveUnitModel then model:Undress(); return end
        if not self:CanFakePreview() then self.previewActive = false; self:RefreshLiveUnit(); return end
        self.previewActive = true
        self.previewUndressed = true
        model:SetUnit("player")
        model:SetCreature(PV_UNDRESS)
    end

    if liveUnitModel then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
        frame:RegisterEvent("UNIT_MODEL_CHANGED")
        frame:SetScript("OnEvent", function(self, event, arg1)
            if not self:IsShown() then return end
            if event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_MODEL_CHANGED" then
                if arg1 ~= "player" then return end
            end
            self:RefreshLiveUnit()
        end)
        frame:HookScript("OnShow", function(self) self:RefreshLiveUnit() end)
    end

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
        if not x then x, y, z = 0, 0, 0 end
        if not facing then facing = 0 end
        model:SetPosition(0, 0, 0)
        model:SetFacing(0)
        model:ClearModel()
        model:SetUnit("player")

        unit = "player"
        _, unitRaceFileName = UnitRace(unit)
        unitSex = UnitSex(unit)

        local sexKey = sex[unitSex] or "male"
        local minX = (modelX.min[unitRaceFileName] and modelX.min[unitRaceFileName][sexKey]) or -0.75
        local maxX = (modelX.max[unitRaceFileName] and modelX.max[unitRaceFileName][sexKey]) or 2.6
        local minZ = (modelZ.min[unitRaceFileName] and modelZ.min[unitRaceFileName][sexKey]) or -1.15
        local maxZ = (modelZ.max[unitRaceFileName] and modelZ.max[unitRaceFileName][sexKey]) or 1.25

        x = x < minX and minX or x > maxX and maxX or x
        z = z < minZ and minZ or z > maxZ and maxZ or z

        model:SetPosition(x, y, z)
        model:SetFacing(facing)
        if model.SetLight then model:SetLight(unpack(defaultLight)) end
    end

    function frame:SetUnit(newUnit)
        local canSet = false
        if newUnit == "player" then
            canSet = true
        elseif UnitIsPlayer(newUnit) and CheckInteractDistance(newUnit, 1) then
            canSet = true
        end
        if canSet then
            local x, y, z = model:GetPosition()
            local facing = model:GetFacing()
            if not x then x, y, z = 0, 0, 0 end
            if not facing then facing = 0 end
            model:SetPosition(0, 0, 0)
            model:SetFacing(0)
            model:ClearModel()
            model:SetUnit(newUnit)
            unit = newUnit
            _, unitRaceFileName = UnitRace(unit)
            unitSex = UnitSex(unit)
            local sexKey = sex[unitSex] or "male"
            local minX = (modelX.min[unitRaceFileName] and modelX.min[unitRaceFileName][sexKey]) or -0.75
            local maxX = (modelX.max[unitRaceFileName] and modelX.max[unitRaceFileName][sexKey]) or 2.6
            local minZ = (modelZ.min[unitRaceFileName] and modelZ.min[unitRaceFileName][sexKey]) or -1.15
            local maxZ = (modelZ.max[unitRaceFileName] and modelZ.max[unitRaceFileName][sexKey]) or 1.25

            x = x < minX and minX or x > maxX and maxX or x
            z = z < minZ and minZ or z > maxZ and maxZ or z

            model:SetPosition(x, y, z)
            model:SetFacing(facing)
        end
    end

    function frame:ClearModel(...) model:ClearModel(...) end
    -- In live-mirror mode TryOn/Undress never put gear on this model — they just
    -- re-stamp the real character so the preview stays perfectly in sync.
    function frame:TryOn(...)
        if liveUnitModel then self:RefreshLiveUnit(); return end
        model:TryOn(...)
    end
    function frame:Undress()
        if liveUnitModel then self:PreviewUndressFaked(); return end
        model:Undress()
    end
    function frame:GetPosition(...) return model:GetPosition(...) end
    function frame:SetPosition(...) model:SetPosition(...) end
    function frame:GetFacing(...) return model:GetFacing(...) end
    function frame:SetFacing(...) model:SetFacing(...) end
    function frame:SetSequence(...) model:SetSequence(...) end
    -- Re-base the preview to a morph's creature display (so a morphed player still sees their
    -- morph in the room). SEH-free pcall guard: an invalid id just leaves the current model.
    function frame:SetDisplayInfo(displayId)
        if model.SetDisplayInfo and displayId and displayId > 0 then
            pcall(model.SetDisplayInfo, model, displayId)
        end
    end
    function frame:SetLight(...) if model.SetLight then model:SetLight(...) end end
    function frame:GetLight(...) if model.GetLight then return model:GetLight(...) end end
    function frame:SetModelAlpha(...) model:SetAlpha(...) end
    function frame:GetModelAlpha(...) return model:GetAlpha(...) end
    function frame:OnUpdateModel(...) model:SetScript("OnUpdateModel", ...) end
    function frame:EnableDragRotation(enable)
        if enable then dragDummy:Show() else dragDummy:Hide() end
    end

    -- ----------------------------------------------------------------
    -- Backward-compatible shims. Older call sites (BottomButtons, Slots,
    -- MorphTab, State) were written for a dual live/preview dressing room.
    -- This room is now a single LIVE mirror of the real character, so each of
    -- them collapses to "keep mirroring" — there is no separate preview state
    -- to toggle. Kept as no-ops / refreshes so none of those callers error.
    -- ----------------------------------------------------------------
    -- Leave any faked preview and re-mirror the REAL character (used after Apply All /
    -- Reset, where the live model should reflect what actually got committed).
    function frame:ShowLive()
        self.previewActive = false
        self.previewUndressed = false
        self:RefreshLiveUnit()
    end
    function frame:ShowPreview() end
    function frame:IsLiveMode() return self.liveUnitModel and true or false end
    function frame:BeginHiddenPreviewSync() end
    function frame:EndHiddenPreviewSync() end

    local originSetBackdrop = frame.SetBackdrop
    function frame:SetBackdrop(backdrop)
        originSetBackdrop(frame, backdrop)
        model:ClearAllPoints()
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

local function IsPositiveItemId(itemId)
    return type(itemId) == "number" and itemId > 0
end

function ns.GetCurrentPreviewSlotItem(slotName)
    local mainFrame = ns.mainFrame
    local slot = mainFrame and mainFrame.slots and mainFrame.slots[slotName]
    if slot then
        if slot.isHiddenSlot then return nil, true end
        if not slot.isMorphed and IsPositiveItemId(slot.itemId) then return slot.itemId, false end
    end

    local equipSlotId = ns.slotToEquipSlotId and ns.slotToEquipSlotId[slotName]
    local state = TransmorpherCharacterState
    if equipSlotId and state then
        if state.HiddenItems and state.HiddenItems[equipSlotId] then
            return nil, true
        end
        local morphed = state.Items and tonumber(state.Items[equipSlotId])
        if morphed then
            if morphed == -1 then return nil, true end
            if morphed > 0 then return morphed, false end
        end
    end

    if slot then
        if IsPositiveItemId(slot.morphedItemId) then return slot.morphedItemId, false end
        if IsPositiveItemId(slot.itemId) then return slot.itemId, false end
    end

    if ns.GetEquippedItemForSlot then
        local equipped = ns.GetEquippedItemForSlot(slotName)
        if IsPositiveItemId(equipped) then return equipped, false end
    end
    return nil, false
end

function ns.BuildPreviewSlotItems(overrides)
    local out, hidden = {}, {}
    for _, slotName in ipairs(ns.slotOrder or {}) do
        local override = overrides and overrides[slotName]
        if override ~= nil then
            local itemId = tonumber(override)
            if itemId and itemId > 0 then
                out[slotName] = itemId
            else
                hidden[slotName] = true
            end
        else
            local itemId, isHidden = ns.GetCurrentPreviewSlotItem(slotName)
            if itemId and itemId > 0 and not isHidden then
                out[slotName] = itemId
            elseif isHidden then
                hidden[slotName] = true
            end
        end
    end
    return out, hidden
end

function ns.DressPreviewModel(model, overrides, opts)
    if not model then return {} end
    opts = opts or {}

    local x, y, z, facing
    if model.GetPosition then x, y, z = model:GetPosition() end
    if model.GetFacing then facing = model:GetFacing() end

    local morphDisplayId = tonumber(opts.morphDisplayId)
    local hasMorph = morphDisplayId and morphDisplayId > 0

    if hasMorph and model.SetDisplayInfo then
        local ok = pcall(model.SetDisplayInfo, model, morphDisplayId)
        if ok then
            if model.Undress then model:Undress() end
        else
            hasMorph = false
        end
    end

    if not hasMorph then
        if opts.reset and model.Reset then
            model:Reset()
        else
            if model.SetUnit then model:SetUnit("player") end
            if model.Undress then model:Undress() end
        end
    end

    if x and model.SetPosition then model:SetPosition(x, y, z) end
    if facing and model.SetFacing then model:SetFacing(facing) end

    local items = ns.BuildPreviewSlotItems(overrides)
    local renderIds = {}
    local mainHand, offHand, ranged

    for _, slotName in ipairs(ns.slotOrder or {}) do
        local itemId = items[slotName]
        if itemId and itemId > 0 then
            if slotName == ns.mainHandSlot or slotName == "Main Hand" then
                mainHand = itemId
            elseif slotName == ns.offHandSlot or slotName == "Off-hand" then
                offHand = itemId
            elseif slotName == ns.rangedSlot or slotName == "Ranged" then
                ranged = itemId
            else
                ns.TryOnPreviewItem(model, itemId, slotName)
                renderIds[#renderIds + 1] = itemId
            end
        end
    end

    if offHand then ns.TryOnPreviewItem(model, offHand, ns.offHandSlot or "Off-hand"); renderIds[#renderIds + 1] = offHand end
    if mainHand then ns.TryOnPreviewItem(model, mainHand, ns.mainHandSlot or "Main Hand"); renderIds[#renderIds + 1] = mainHand end
    if ranged and not mainHand and not offHand then
        ns.TryOnPreviewItem(model, ranged, ns.rangedSlot or "Ranged")
        renderIds[#renderIds + 1] = ranged
    end

    return renderIds
end
