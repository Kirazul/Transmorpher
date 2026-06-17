local addon, ns = ...


local itemBackdrop = { -- small "DressingRoom"s
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
}
local itemBackdropColor = {0.055, 0.045, 0.032, 0.98}
local itemBackdropBorderColor = {0.62, 0.48, 0.18, 0.9}
local selectedItemBackdropBorderColor = {1.00, 0.82, 0.24, 1.00}
local previewHighlightTexture = "Interface\\Buttons\\ButtonHilight-Square"
local MIN_ITEM_PREVIEW_ROWS = 3


local function getIndexOf(array, value)
    for i, v in ipairs(array) do
        if v == value then return i end
    end
    return nil
end

--[[
    Methods:
        GetPage
        SetPage
        GetPageCount
        SetItems(itemIds) // takes a list of integers
        SetupModel(self, width, height, x, y, z, facing, sequence)
        Update
        TryOn(item)

        Call `Update` method manually after all Set- methods. TryOn 
        items several times in the same frame can give sometimes 
        unexpected result.
]]

local function DressingRoom_OnUpdateModel(self)
    self:SetSequence(self:GetParent():GetParent().dressingRoomSetup.sequence)
end

local function MakeSetupKey(width, height, x, y, z, facing, sequence)
    return tostring(width or 0) .. ":" .. tostring(height or 0) .. ":" .. tostring(x or 0) .. ":" .. tostring(y or 0) .. ":" .. tostring(z or 0) .. ":" .. tostring(facing or 0) .. ":" .. tostring(sequence or 0)
end

local function MakeRenderKey(self, itemId)
    return (self.setupKey or "") .. ":" .. tostring(self.itemsVersion or 0) .. ":" .. tostring(itemId or "") .. ":" .. tostring(self.tryOnItem or "") .. ":" .. tostring(self.previewSlotName or "")
end

local function UpdateSelectionBorder(self, dr)
    if dr.itemId == self.selectedItemId then
        dr:SetBackdropBorderColor(unpack(selectedItemBackdropBorderColor))
    else
        dr:SetBackdropBorderColor(unpack(itemBackdropBorderColor))
    end
end

local function InvalidateRenderedItems(self)
    self.itemsVersion = (self.itemsVersion or 0) + 1
    for _, dr in ipairs(self.dressingRooms) do
        dr.renderKey = nil
        dr.pendingRenderKey = nil
        dr.isQuerying = false
    end
end


local function button_OnClick(self, button)
    local mainFrame = self:GetParent():GetParent()
    local onItemClick = mainFrame.onItemClick
    local clickedId = self:GetParent().itemId
    mainFrame.selectedItemId = clickedId
    mainFrame.selectedItemIndex = self:GetParent().itemIndex
    if clickedId ~= nil then
        for _, dr in ipairs(mainFrame.dressingRooms) do
            if dr.itemId == clickedId then
                dr:SetBackdropBorderColor(unpack(selectedItemBackdropBorderColor))
            else
                dr:SetBackdropBorderColor(unpack(itemBackdropBorderColor))
            end
        end
    end
    if onItemClick ~= nil then
        onItemClick(self, button)
    end
    if button == "LeftButton" then
        PlaySound("gsTitleOptionOK")
    end
end


local function button_OnEnter(self, ...)
    local onEnter = self:GetParent():GetParent().onEnter
    if onEnter ~= nil then
        onEnter(self, ...)
    end
end


local function button_OnLeave(self, ...)
    local onLeave = self:GetParent():GetParent().onLeave
    if onLeave ~= nil then
        onLeave(self, ...)
    end
end


local recycler = {
    ["recycled"] = {},
    ["counter"] = 0,

    ["get"] = function(self, parent, number)
        local result = {}
        while #result < number do
            if self.recycled[parent] == nil then self.recycled[parent] = {} end
            local recycled = self.recycled[parent]
            if #recycled > 0 then
                table.insert(result, table.remove(recycled))
            else
                self.counter = self.counter + 1
                local dr = ns.CreateDressingRoom("$parentDressingRoom"..self.counter, parent)
                dr:SetBackdrop(itemBackdrop)
                dr:SetBackdropColor(unpack(itemBackdropColor))
                dr:SetBackdropBorderColor(unpack(itemBackdropBorderColor))
                dr:EnableDragRotation(false)
                dr:EnableMouseWheel(false)
                dr.queriedLabel = dr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dr.queriedLabel:SetJustifyH("LEFT")
                dr.queriedLabel:SetHeight(18)
                dr.queriedLabel:SetPoint("CENTER", dr, "CENTER", 0, 0)
                dr.queriedLabel:SetText("Queried...")
                dr.queriedLabel:Hide()
                dr.queryFailedLabel = dr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dr.queryFailedLabel:SetJustifyH("LEFT")
                dr.queryFailedLabel:SetHeight(18)
                dr.queryFailedLabel:SetPoint("CENTER", dr, "CENTER", 0, 0)
                dr.queryFailedLabel:SetText("Query failed")
                dr.queryFailedLabel:Hide()
                dr.queryFailedLabel = dr.queryFailedLabel
                local btn = CreateFrame("Button", "$parent".."Button", dr)
                btn:SetAllPoints()
                btn:SetHighlightTexture(previewHighlightTexture)
                btn:EnableMouse(true)
                btn:RegisterForClicks("LeftButtonUp")
                btn:SetScript("OnEnter", button_OnEnter)
                btn:SetScript("OnLeave", button_OnLeave)
                btn:SetScript("OnClick", button_OnClick)
                dr.button = btn
                table.insert(result, 1, dr)
            end
        end
        return result
    end,

    ["recycle"] = function(self, parent, dr)
        if self.recycled[parent] == nil then self.recycled[parent] = {} end
        local recycled = self.recycled[parent]
        for i, v in pairs(recycled) do
            assert(dr ~= v, "Double recycling.")
        end
        dr:ClearModel()
        dr.renderKey = nil
        dr.pendingRenderKey = nil
        dr:Hide()
        table.insert(recycled, dr)
    end,
}


local function PreviewList_SetItems(self, itemIds)
    local wasCustom = self.customEntries ~= nil
    self.customEntries = nil
    local changed = wasCustom or #self.itemIds ~= #itemIds
    if not changed then
        for i = 1, #itemIds do
            if self.itemIds[i] ~= itemIds[i] then
                changed = true
                break
            end
        end
    end
    table.wipe(self.itemIds)
    for i=1, #itemIds do
        table.insert(self.itemIds, itemIds[i])
    end
    if changed then
        InvalidateRenderedItems(self)
    end
    self.selectedItemId = nil
    self.selectedItemIndex = nil
end


local function PreviewList_SetupModel(self, width, height, x, y, z, facing, sequence)
    local source = self.customEntries or self.itemIds
    assert(#source > 0, "`SetItemIds` first.")
    self.dressingRoomSetup = {
        ["width"] = width,
        ["height"] = height,
        ["x"] = x,
        ["y"] = y,
        ["z"] = z,
        ["facing"] = facing,
        ["sequence"] = sequence,
    }
    local setupKey = MakeSetupKey(width, height, x, y, z, facing, sequence)
    if self.setupKey ~= setupKey then
        self.setupKey = setupKey
        for _, dr in ipairs(self.dressingRooms) do
            dr.renderKey = nil
            dr.pendingRenderKey = nil
            dr.isQuerying = false
        end
    end
    local countW = math.max(1, math.floor(self:GetWidth() / width))
    local minRows = self.customEntries and 1 or (self.minRows or MIN_ITEM_PREVIEW_ROWS)
    local countH = math.max(minRows, math.floor(self:GetHeight() / height))
    local perPage = countW * countH
    if perPage > 0 then
        if #self.dressingRooms < perPage then
            local list = recycler:get(self, perPage - #self.dressingRooms)
            while #list > 0 do
                local dr = table.remove(list)
                dr:SetWidth(width)
                dr:SetHeight(height)
                table.insert(self.dressingRooms, dr)
            end
        elseif #self.dressingRooms > perPage then
            while #self.dressingRooms > perPage do
                local dr = table.remove(self.dressingRooms)
                dr:OnUpdateModel(nil)
                recycler:recycle(self, dr)
            end
        end
        local gapW = math.max(6, (self:GetWidth() - countW * width) / 2)
        local gapH = 6
        for h = 1, countH do
            for w = 1, countW do
                local dr = self.dressingRooms[(h - 1) * countW + w]
                dr:ClearAllPoints()
                dr:SetPoint("TOPLEFT", self, "TOPLEFT", width * (w - 1) + gapW , -height * (h - 1) - gapH)
                dr:SetSize(width, height)
                dr:SetBackdropBorderColor(unpack(itemBackdropBorderColor))
            end
        end
    end
end

local function PreviewList_GetItemIndex(self, sourceCount, slotIndex)
    local perPage = #self.dressingRooms
    if perPage <= 0 then return nil end
    local page = self.currentPage or 1
    return (page - 1) * perPage + slotIndex
end


local function PreviewList_SetPage(self, page)
    assert(type(page) == "number", "`page` must be a positive number.")
    self.currentPage = page
end


local function PreviewList_GetPage(self)
    return self.currentPage
end


local function PreviewList_GetPageCount(self)
    local source = self.customEntries or self.itemIds
    if #source == 0 or #self.dressingRooms == 0 then
        return 0
    end
    return math.ceil(#source/#self.dressingRooms)
end


local function PreviewList_TryOnItem(dr, itemId, slotName)
    if ns.TryOnPreviewItem then ns.TryOnPreviewItem(dr, itemId, slotName)
    else dr:TryOn(itemId) end
end

local function PreviewList_RenderItem(dr, itemId, parent)
    parent = parent or dr:GetParent()
    dr:Reset()
    dr:Undress()
    local setup = parent.dressingRoomSetup
    dr:SetPosition(setup.x, setup.y, setup.z)
    dr:SetFacing(setup.facing)
    PreviewList_TryOnItem(dr, itemId, parent.previewSlotName)
    if parent.tryOnItem ~= nil then
        PreviewList_TryOnItem(dr, parent.tryOnItem, parent.tryOnItemSlotName or parent.previewSlotName)
    end
    dr:SetSequence(setup.sequence)
    dr.button:Show()
    dr:OnUpdateModel(DressingRoom_OnUpdateModel)
    dr.renderKey = MakeRenderKey(parent, itemId)
end

local function queryItemHandler(functable, itemId, success)
    local dr = functable.dressingRoom
    if dr.itemId == itemId then
        dr.queriedLabel:Hide()
        dr.isQuerying = false
        if success then
            PreviewList_RenderItem(dr, itemId)
        else
            dr.queryFailedLabel:Show()
        end
    end
end

local function PreviewList_Update(self)
    if self.dressingRoomSetup == nil then return end
    if self.customEntries ~= nil then
        local perPage = #self.dressingRooms
        if perPage <= 0 then return end
        for i = 1, perPage do
            local dr = self.dressingRooms[i]
            local itemIndex = PreviewList_GetItemIndex(self, #self.customEntries, i)
            local entry = self.customEntries[itemIndex]
            if entry == nil then
                dr:OnUpdateModel(nil)
                dr:ClearModel()
                dr:Hide()
            else
                dr.itemId = entry.id
                dr.itemIndex = itemIndex
                dr.isQuerying = false
                dr:Show()
                dr:Reset()
                dr:Undress()
                dr:SetModelAlpha(1)
                dr:SetLight(1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64)
                local setup = self.dressingRoomSetup
                dr:SetPosition(setup.x, setup.y, setup.z)
                dr:SetFacing(setup.facing)
                dr.button:Show()
                dr.queriedLabel:Hide()
                dr.queryFailedLabel:Hide()
                if self.customRenderer then
                    self.customRenderer(dr, entry, self)
                end
                UpdateSelectionBorder(self, dr)
            end
        end
        return
    end
    if #self.itemIds == 0 then
        -- Nothing to display — hide all dressing rooms
        for _, dr in ipairs(self.dressingRooms) do
            dr:OnUpdateModel(nil)
            dr:ClearModel()
            dr.renderKey = nil
            dr.pendingRenderKey = nil
            dr:Hide()
        end
        return
    end
    local perPage = #self.dressingRooms
    for i, dr in ipairs(self.dressingRooms) do
        local dr = self.dressingRooms[i]
        local itemIndex = PreviewList_GetItemIndex(self, #self.itemIds, i)
        local itemId = self.itemIds[itemIndex]
        if itemId == nil then
            dr:OnUpdateModel(nil)
            dr:ClearModel()
            dr:Hide()
        else
            dr.itemId = itemId
            dr.itemIndex = itemIndex
            dr.isQuerying = true
            dr:Show()
            dr:OnUpdateModel(nil)
            dr:ClearModel()
            dr.renderKey = nil
            dr.pendingRenderKey = nil
            dr.button:Hide()
            dr.queriedLabel:Show()
            dr.queryFailedLabel:Hide()
            local handler = {
                ["dressingRoom"] = dr,
                ["__call"] = queryItemHandler,}
            setmetatable(handler, handler)
            ns.QueryItem(itemId, handler)
            UpdateSelectionBorder(self, dr)
        end
    end
end


local function PreviewList_SelectByItemId(self, itemId)
    local source = self.customEntries or self.itemIds
    local index = nil
    if self.customEntries then
        for i, entry in ipairs(source) do
            if entry.id == itemId then
                index = i
                break
            end
        end
    else
        index = getIndexOf(source, itemId)
    end
    if index ~= nil then
        self.selectedItemId = itemId
        self.selectedItemIndex = index
        for _, dr in ipairs(self.dressingRooms) do
            if dr.itemId == itemId then
                dr:SetBackdropBorderColor(unpack(selectedItemBackdropBorderColor))
            else
                dr:SetBackdropBorderColor(unpack(itemBackdropBorderColor))
            end
        end
    end
end


local function PreviewList_TryOn(self, item)
    local changed = self.tryOnItem ~= item
    self.tryOnItem = item
    if changed then
        for _, dr in ipairs(self.dressingRooms) do
            dr.renderKey = nil
            dr.pendingRenderKey = nil
        end
    end
    if item ~= nil then
        for i, dr in ipairs(self.dressingRooms) do
            if dr:IsVisible() and not dr.isQuerying then
                PreviewList_TryOnItem(dr, item, self.tryOnItemSlotName or self.previewSlotName)
            end
        end
    end
end

local function PreviewList_SetCustomEntries(self, entries)
    table.wipe(self.itemIds)
    local changed = self.customEntries ~= entries
    if entries then
        self.customEntries = entries
    else
        self.customEntries = nil
    end
    if changed then
        InvalidateRenderedItems(self)
    end
    self.selectedItemId = nil
    self.selectedItemIndex = nil
end

local function PreviewList_SetCustomRenderer(self, renderer)
    self.customRenderer = renderer
    self.customRendererVersion = (self.customRendererVersion or 0) + 1
end


function ns.CreatePreviewList(parent)
    local frame = CreateFrame("Frame", addon.."PreviewList", parent)

    frame.itemIds = {}
    frame.dressingRooms = {}
    frame.currentPage = 1
    frame.itemsVersion = 0
    frame.dressingRoomSetup = nil
    frame.customEntries = nil
    frame.customRenderer = nil
    frame.customRendererVersion = 0
    frame.minRows = MIN_ITEM_PREVIEW_ROWS
    frame.onEnter = nil
    frame.onLeave = nil
    frame.onItemClick = nil

    frame.selectedItemId = nil
    frame.selectedItemIndex = nil

    frame.SetItems = PreviewList_SetItems
    frame.Update = PreviewList_Update
    frame.SetupModel = PreviewList_SetupModel
    frame.GetPage = PreviewList_GetPage
    frame.SetPage = PreviewList_SetPage
    frame.GetPageCount = PreviewList_GetPageCount
    frame.SelectByItemId = PreviewList_SelectByItemId
    frame.TryOn = PreviewList_TryOn
    frame.SetCustomEntries = PreviewList_SetCustomEntries
    frame.SetCustomRenderer = PreviewList_SetCustomRenderer

    frame:SetScript("OnShow", function(self)
        if self.dressingRoomSetup ~= nil then
            self:Update()
        end
    end)

    return frame
end
