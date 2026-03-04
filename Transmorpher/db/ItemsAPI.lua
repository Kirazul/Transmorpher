local addon, ns = ...
local items = ns.items


local function getIndex(array, value)
    for i = 1, #array do
        if array[i] == value then
            return i
        end
    end
    return nil
end


-- Returns all the appearances for the given slot/subclass.
function ns.GetSubclassRecords(whatSlot, whatSubclass)
    assert(type(whatSlot) == "string", "'slot' is mandatroy and must be 'string'.")
    assert(type(whatSubclass) == "string", "'subclass' is mandatroy and must be 'string' but given `"..tostring(whatSubclass).."`.")
    local slotData = items[whatSlot] == nil and items["Armor"][whatSlot] or items[whatSlot]
    return slotData[whatSubclass]
end


-- Returns a table {[itemId] = "itemName",} of other items with the same appearance
-- (display id) as the item with the given id including the given id.
-- 'subclass' can be nil. Also returns 'subclass' as second value if nil.
function ns.FindRecord(whatSlot, whatItem)
    assert(type(whatSlot) == "string", "'slot' is mandatroy and must be 'string'.")
    assert(type(whatItem) == "number", "'itemId' is mandatroy and must be integer.")
    local slotData = items[whatSlot] == nil and items["Armor"][whatSlot] or items[whatSlot]
    for subclass, subclassRecords in pairs(slotData) do
        for _, data in pairs(subclassRecords) do
            local ids = data[1]
            local names = data[2]
            local index = getIndex(ids, whatItem)
            if index ~= nil then
                return ids, names, index, subclass
            end
        end
    end
end