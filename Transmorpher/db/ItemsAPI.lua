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
    
    -- 1. Try searching in the explicitly requested slot
    local slotData = items[whatSlot] or (items["Armor"] and items["Armor"][whatSlot])
    if slotData and slotData[whatSubclass] then
        return slotData[whatSubclass]
    end

    -- 2. Fallback: Search top-level (some weapons/off-hands are stored as top-level keys)
    if items[whatSubclass] then
        return items[whatSubclass]
    end

    -- 3. Fallback: Search across weapon slots if it's a known weapon/off-hand subclass
    local weaponSlots = {"Main Hand", "Off-hand", "Ranged"}
    for _, slot in ipairs(weaponSlots) do
        if items[slot] and items[slot][whatSubclass] then
            return items[slot][whatSubclass]
        end
    end

    return nil
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