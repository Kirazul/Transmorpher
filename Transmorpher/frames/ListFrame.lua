local addon, ns = ...



local function button_OnClick(self)
    self:GetParent():Select(self:GetID())
end


local recycler = {
    ["recycled"] = {},
    ["counter"] = 0,

    ["get"] = function(self, parent, number)
        number = number ~= nil and number or 1
        local result = {}
        while #result < number do
            if self.recycled[parent] == nil then self.recycled[parent] = {} end
            local recycled = self.recycled[parent]
            if #self.recycled > 0 then
                table.insert(result, table.remove(recycled))
            else
                self.counter = self.counter + 1
                local btn = CreateFrame("Button", "$parentListFrameButton"..self.counter, parent, "OptionsListButtonTemplate")
                btn:SetID(0)
                btn:Show()
                btn:SetScript("OnClick", button_OnClick)
                table.insert(result, 1, btn)
            end
        end
        return #result > 1 and result or result[1]
    end,

    ["recycle"] = function(self, parent, btn)
        if self.recycled[parent] == nil then self.recycled[parent] = {} end
        local recycled = self.recycled[parent]
        for i, v in ipairs(recycled) do
            assert(btn ~= v, "Double recycling.")
        end
        btn:Hide()
        table.insert(recycled, btn)
    end,
}


local function ListFrame_SetInsets(self, left, right, top, bottom)
    self.insets.left = left
    self.insets.right = right
    self.insets.top = top
    self.insets.bottom = bottom
    self:Update()
end


local function ListFrame_GetListHeight(self)
    local height = 0
    for _, btn in pairs(self.buttons) do
        height = height + btn:GetHeight()
    end
    return height
end


local function ListFrame_Select(self, id)
    if self.selected ~= nil then
        self.buttons[self.selected]:UnlockHighlight()
    end
    if type(id) == "number" then
        self.buttons[id]:LockHighlight()
        self.selected = id
        if self.onSelect ~= nil then
            self.onSelect(self, id)
        end
    elseif type(id) == "string" then
        for i = 1, #self.buttons do
            if self.buttons[i]:GetText() == id then
                self.buttons[i]:LockHighlight()
                self.selected = i
                if self.onSelect ~= nil then
                    self.onSelect(self, i)
                end
                break
            end
        end
    end
end


local function ListFrame_Deselect(self)
    if self.selected ~= nil then
        self.buttons[self.selected]:UnlockHighlight()
        local selected = self.selected
        self.selected = nil
        return selected
    end
end


local function ListFrame_GetSelected(self)
    return self.selected
end


local function ListFrame_GetButton(self, nameOrId)
    if type(nameOrId) == "string" then
        for i = 1, #self.buttons do
            if self.buttons[i].name == nameOrId then
                return self.buttons[i]
            end
        end
    elseif type(nameOrId) == "number" then
        return self.buttons[nameOrId]
    end
end


local function ListFrame_RemoveItem(self, id)
    if #self.buttons >= id and id > 0 then
        if self.selected ~= nil then
            if self.selected == id then
                self:Deselect()
            elseif self.selected > id then
                self.selected = self.selected - 1
            end
        end
        for i = id + 1, #self.buttons do
            self.buttons[i]:SetID(i - 1)
        end 
        local btn = table.remove(self.buttons, id)
        btn:ClearAllPoints()
        recycler:recycle(self, btn)
        self:Update()
    end
end


local function ListFrame_Clear(self)
    if self:GetSelected() ~= nil then
        self:Deselect()
    end
    while #self.buttons > 0 do
        local btn = table.remove(self.buttons, #self.buttons)
        btn:ClearAllPoints()
        recycler:recycle(self, btn)
    end
    self:Update()
end


local function ListFrame_Update(self)
    self:SetHeight(self:GetListHeight() + self.insets.top + self.insets.bottom)
    if #self.buttons > 0 then
        self.buttons[1]:SetPoint("TOPLEFT", self.insets.left, -self.insets.top)
        self.buttons[1]:SetPoint("TOPRIGHT", -self.insets.right, self.insets.bottom)
        for i=2, #self.buttons do
            self.buttons[i]:SetPoint("TOPLEFT", self.buttons[i - 1], "BOTTOMLEFT")
            self.buttons[i]:SetPoint("TOPRIGHT", self.buttons[i - 1], "BOTTOMRIGHT")
        end
    end
end


local function ListFrame_AddItem(self, itemName)
    assert(type(itemName) == "string", "Item name must be a 'string' value.")
    local btn = recycler:get(self)
    btn:SetText(itemName)
    btn:SetScript("OnClick", button_OnClick)
    btn.name = itemName
    table.insert(self.buttons, btn)
    btn:SetID(#self.buttons)
    if self.GetListHeight ~= nil then
        self:SetHeight(self:GetListHeight())
    end
    self:Update()
    return #self.buttons
end


local function ListFrame_GetSize(self)
    return #self.buttons
end


function ns.CreateListFrame(name, list, parent)
    local frame = CreateFrame("Frame", name, parent)
    frame.insets = {left = 0, right = 0, top = 0, bottom = 0}
    frame.buttons = {}
    frame.selected = nil
    frame.onSelect = nil

    frame.SetInsets = ListFrame_SetInsets
    frame.GetListHeight = ListFrame_GetListHeight
    frame.GetSelected = ListFrame_GetSelected
    frame.GetButton = ListFrame_GetButton
    frame.Select = ListFrame_Select
    frame.Deselect = ListFrame_Deselect
    frame.AddItem = ListFrame_AddItem
    frame.RemoveItem = ListFrame_RemoveItem
    frame.Clear = ListFrame_Clear
    frame.Update = ListFrame_Update
    frame.GetSize = ListFrame_GetSize

    if list ~= nil then
        for _, name in pairs(list) do
            ListFrame_AddItem(frame, name)
        end
    end

    return frame
end
