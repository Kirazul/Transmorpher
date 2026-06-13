local addon, ns = ...

local QUERY_TIME = 180
local PERIOD = 0.1


local tooltip = CreateFrame("GameTooltip", nil, UIParent)
local dummy = CreateFrame("Frame", nil, UIParent)
dummy.queries = {} -- [itemId] = {functable1, functable2, fuctable3, ...}
dummy.elapsed = 0.0


local function dummy_OnUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= PERIOD then
        local onRemove = {}
        for itemId, handlers in pairs(self.queries) do
            local itemName, itemLink = GetItemInfo(itemId)
            local i = #handlers
            while i >= 1 do
                local h = handlers[i]
                h.time = h.time - elapsed
                if itemLink ~= nil or h.time <= 0 then
                    h(itemId, itemLink ~= nil)
                    table.remove(handlers, i)
                end
                i = i - 1
            end
            if #handlers == 0 then
                table.insert(onRemove, itemId)
            end
        end
        while #onRemove > 0 do
            self.queries[table.remove(onRemove)] = nil
        end
        if next(self.queries) == nil then
            self:SetScript("OnUpdate", nil)
        end
    end
end


function ns.QueryItem(itemId, handler)
    assert(type(itemId) == "number", "`itemId` must be a number.")
    assert( type(handler) == "nil" or
            type(handler) == "function" or
            (type(handler) == "table" and getmetatable(handler) ~= nil and getmetatable(handler)["__call"] ~= nil),
            "'handler' must be a callable object (a function or a functable).")
    local itemName, itemLink = GetItemInfo(itemId)
    if itemLink ~= nil then
        if handler ~= nil then
            handler(itemId, true)
        end
    else
        local queries = dummy.queries
        if queries[itemId] == nil then
            tooltip:SetHyperlink("item:".. tostring(itemId) ..":0:0:0:0:0:0:0")
            queries[itemId] = {}
        end
        local functable = {
            ["__call"] = function(self, itemId, success) 
                if handler ~= nil then
                    handler(itemId, success)
                end
            end,
            ["time"] = QUERY_TIME,
        }
        setmetatable(functable, functable)
        table.insert(queries[itemId], 1, functable)
        if dummy:GetScript("OnUpdate") == nil then
            dummy:SetScript("OnUpdate", dummy_OnUpdate)
        end
    end
end