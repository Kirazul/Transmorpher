local addon, ns = ...

-- ============================================================
-- LOADOUT EXPORT / IMPORT CODEC (TM1)
--
-- Format: TM1|1|name|items|hidden|emh|eoh|mount|mhidden|pet|hpet|hpscale100|morph|mscale100|title|mounts
--   Field 2 is always version "1" (avoids ambiguous parses with loadout names).
-- Legacy misaligned exports (TM1|name|0|<items>|...) are auto-corrected on import.
-- ============================================================

local FORMAT_TAG = "TM1"
local FORMAT_VERSION = "1"
local EMPTY_HIDDEN_MARKER = "-"
local DEFAULT_IMPORT_NAME = "Imported Loadout"

local function GetSlotCount()
    return #(ns.slotOrder or {})
end

local function CountCommas(str)
    if not str or str == "" then return 0 end
    local n = 0
    for _ in str:gmatch(",") do
        n = n + 1
    end
    return n
end

local function LooksLikeItemCsv(str)
    if not str or str == "" then return false end
    if not str:match("^%-?%d") then
        return false
    end
    local minCommas = math.max(8, GetSlotCount() - 2)
    return CountCommas(str) >= minCommas
end

local function LooksLikeHiddenCsv(str)
    if not str or str == "" then return false end
    return str:find(",") ~= nil and str:match("^[01,]+$") ~= nil
end

local function FindItemsFieldIndex(parts, startIdx)
    for i = startIdx, #parts do
        if LooksLikeItemCsv(parts[i]) then
            return i
        end
    end
    return nil
end

local function BuildItemsCsv(items, slotCount)
    local parts = {}
    for i = 1, slotCount do
        parts[i] = tostring((items and items[i]) or 0)
    end
    return table.concat(parts, ",")
end

local function BuildHiddenCsv(hiddenSlots, items, slotCount)
    local hiddenParts = {}
    local anyHidden = false
    for i = 1, slotCount do
        local hidden = (hiddenSlots and hiddenSlots[i]) and 1 or 0
        if items and items[i] and items[i] < 0 then
            hidden = 1
        end
        if hidden == 1 then anyHidden = true end
        hiddenParts[i] = tostring(hidden)
    end
    if anyHidden then
        return table.concat(hiddenParts, ",")
    end
    return EMPTY_HIDDEN_MARKER
end

local function ParseSpecialFields(parts, idx)
    -- Legacy misaligned: |0|0|0|mount|... (empty hidden exported as extra pipe zeros)
    if parts[idx] == "0" and parts[idx + 1] == "0" and parts[idx + 2] == "0" then
        local mountVal = tonumber(parts[idx + 3])
        if mountVal and mountVal > 0 then
            return {"", "0", "0", parts[idx + 3], parts[idx + 4], parts[idx + 5],
                parts[idx + 6], parts[idx + 7], parts[idx + 8], parts[idx + 9], parts[idx + 10], parts[idx + 11]}
        end
    end
    if parts[idx] == "0" and parts[idx + 1] == "0" then
        local mountVal = tonumber(parts[idx + 2])
        if mountVal and mountVal > 0 then
            return {"", "0", "0", parts[idx + 2], parts[idx + 3], parts[idx + 4],
                parts[idx + 5], parts[idx + 6], parts[idx + 7], parts[idx + 8], parts[idx + 9], parts[idx + 10]}
        end
    end
    return nil
end

-- Remove a lone "0" field between TM1|1|name| and the item CSV (export-time only).
local function SanitizeExportString(encoded)
    if not encoded then return encoded end
    return encoded:gsub("^TM1|1|([^|]+)|0|(%d)", "TM1|1|%1|%2", 1)
end

local function EscapeName(name)
    if not name or name == "" then return "" end
    return name:gsub("|", "~")
end

local function UnescapeName(name)
    if not name or name == "" then return DEFAULT_IMPORT_NAME end
    return name:gsub("~", "|")
end

local function SplitPipe(encoded)
    local parts = {}
    local start = 1
    while true do
        local pos = encoded:find("|", start, true)
        if not pos then
            parts[#parts + 1] = encoded:sub(start)
            break
        end
        parts[#parts + 1] = encoded:sub(start, pos - 1)
        start = pos + 1
    end
    return parts
end

local function ParseItemList(str)
    local items = {}
    local slotCount = GetSlotCount()
    if not str or str == "" or slotCount < 1 then return items end
    local idx = 1
    for token in string.gmatch(str, "[^,]+") do
        if idx > slotCount then break end
        items[idx] = tonumber(token) or 0
        idx = idx + 1
    end
    return items
end

local function ParseHiddenList(str, items)
    local hiddenSlots = {}
    local slotCount = GetSlotCount()
    if not str or str == "" then
        for i = 1, slotCount do
            local itemId = items[i]
            if itemId and itemId < 0 then
                hiddenSlots[i] = true
            end
        end
        return hiddenSlots
    end
    local idx = 1
    for token in string.gmatch(str, "[^,]+") do
        if idx > slotCount then break end
        if token == "1" then
            hiddenSlots[idx] = true
        end
        idx = idx + 1
    end
    for i = 1, slotCount do
        local itemId = items[i]
        if itemId and itemId < 0 then
            hiddenSlots[i] = true
        end
    end
    return hiddenSlots
end

local function ParseMountsList(str)
    local mounts = {}
    if not str or str == "" then return mounts end
    for pair in string.gmatch(str, "[^;]+") do
        local spellId, displayId = pair:match("^(%d+):(%d+)$")
        spellId = tonumber(spellId)
        displayId = tonumber(displayId)
        if spellId and displayId and displayId > 0 then
            mounts[spellId] = displayId
        end
    end
    return mounts
end

function ns.NormalizeLoadoutTable(loadout)
    if not loadout then return nil end
    local slotCount = GetSlotCount()
    if slotCount < 1 then return nil end

    local normalized = {
        name = loadout.name,
        items = {},
        hiddenSlots = {},
        enchantMH = loadout.enchantMH,
        enchantOH = loadout.enchantOH,
        mountDisplay = loadout.mountDisplay,
        mountHidden = loadout.mountHidden,
        petDisplay = loadout.petDisplay,
        combatPetDisplay = loadout.combatPetDisplay,
        combatPetScale = loadout.combatPetScale,
        morphForm = loadout.morphForm,
        morphScale = loadout.morphScale,
        titleID = loadout.titleID,
        mounts = {},
        uid = loadout.uid,
    }

    local rawItems = loadout.items
    if type(rawItems) == "string" then
        normalized.items = ParseItemList(rawItems)
    elseif type(rawItems) == "table" then
        for i = 1, slotCount do
            local v = rawItems[i]
            if v == nil and ns.slotOrder then
                v = rawItems[ns.slotOrder[i]]
            end
            normalized.items[i] = tonumber(v) or 0
        end
    else
        for i = 1, slotCount do
            normalized.items[i] = 0
        end
    end

    local rawHidden = loadout.hiddenSlots
    if type(rawHidden) == "table" then
        for i = 1, slotCount do
            if rawHidden[i] then
                normalized.hiddenSlots[i] = true
            end
        end
    end
    for i = 1, slotCount do
        if normalized.items[i] and normalized.items[i] < 0 then
            normalized.hiddenSlots[i] = true
        end
    end

    if loadout.mounts then
        for spellId, displayId in pairs(loadout.mounts) do
            if spellId and displayId and displayId > 0 then
                normalized.mounts[spellId] = displayId
            end
        end
    end

    return normalized
end

function ns.SerializeLoadout(loadout)
    if loadout then
        loadout.isCurrent = nil
    end
    loadout = ns.NormalizeLoadoutTable(loadout)
    local slotCount = GetSlotCount()
    if not loadout or slotCount < 1 then
        return nil, "invalid loadout"
    end

    local name = EscapeName(loadout.name)
    local itemsCsv = BuildItemsCsv(loadout.items, slotCount)
    local hiddenCsv = BuildHiddenCsv(loadout.hiddenSlots, loadout.items, slotCount)

    local hps = 100
    if loadout.combatPetScale then
        hps = math.floor(loadout.combatPetScale * 100 + 0.5)
    end
    local ms = 100
    if loadout.morphScale then
        ms = math.floor(loadout.morphScale * 100 + 0.5)
    end

    local mountParts = {}
    for spellId, displayId in pairs(loadout.mounts) do
        mountParts[#mountParts + 1] = tostring(spellId) .. ":" .. tostring(displayId)
    end
    table.sort(mountParts)
    local mountsCsv = (#mountParts > 0) and table.concat(mountParts, ";") or ""

    local encoded = string.format(
        "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s",
        FORMAT_TAG,
        FORMAT_VERSION,
        name,
        itemsCsv,
        hiddenCsv,
        tostring(loadout.enchantMH or 0),
        tostring(loadout.enchantOH or 0),
        tostring(loadout.mountDisplay or 0),
        loadout.mountHidden and "1" or "0",
        tostring(loadout.petDisplay or 0),
        tostring(loadout.combatPetDisplay or 0),
        tostring(hps),
        tostring(loadout.morphForm or 0),
        tostring(ms),
        tostring(loadout.titleID or 0),
        mountsCsv
    )

    return SanitizeExportString(encoded), nil
end


function ns.DeserializeLoadoutString(encoded)
    if type(encoded) ~= "string" then
        return nil, "export string must be text"
    end

    encoded = encoded:match("^%s*(.-)%s*$")
    if encoded == "" then
        return nil, "export string is empty"
    end

    -- Fix double pipes caused by WoW EditBox escaping
    encoded = encoded:gsub("||", "|")

    -- Strip trailing pipe if present (export always adds one via empty mounts field)
    if encoded:sub(-1) == "|" then
        encoded = encoded:sub(1, -2)
    end

    if encoded:sub(1, #FORMAT_TAG) ~= FORMAT_TAG then
        return nil, "unsupported export string (expected " .. FORMAT_TAG .. ")"
    end

    local parts = SplitPipe(encoded)

    if parts[1] ~= FORMAT_TAG then
        return nil, "unsupported export string (expected " .. FORMAT_TAG .. ")"
    end

    -- ============================================================
    -- SCHEMA-AWARE PARSING
    -- Dynamically maps remaining fields based on export structure,
    -- allowing backward compatibility with older string versions.
    -- ============================================================

    local idx = 2

    -- Skip version field if present
    if parts[idx] == FORMAT_VERSION then
        idx = idx + 1
    end

    -- Extract name
    local name = parts[idx] or ""
    idx = idx + 1

    -- Locate items CSV by pattern (handles variable-length prefixes)
    local itemsIdx = FindItemsFieldIndex(parts, idx)
    if not itemsIdx then
        return nil, "export string is missing item data (copy the full string)"
    end
    local itemsStr = parts[itemsIdx]
    idx = itemsIdx + 1

    -- Detect hidden CSV
    local hiddenStr = ""
    if parts[idx] == EMPTY_HIDDEN_MARKER then
        hiddenStr = ""
        idx = idx + 1
    elseif LooksLikeHiddenCsv(parts[idx]) then
        hiddenStr = parts[idx]
        idx = idx + 1
    end

    -- Check for legacy misaligned fields
    local remaining = ParseSpecialFields(parts, idx)
    if not remaining then
        remaining = {}
        for i = idx, #parts do
            table.insert(remaining, parts[i])
        end
    end

    -- Map remaining fields dynamically (schema-aware)
    local emh       = remaining[1] or "0"
    local eoh       = remaining[2] or "0"
    local mount     = remaining[3] or "0"
    local mhidden   = remaining[4] or "0"
    local pet       = remaining[5] or "0"
    local hpet      = remaining[6] or "0"
    local hpscale100 = remaining[7] or "100"
    local morph     = remaining[8] or "0"
    local mscale100 = remaining[9] or "100"
    local title     = remaining[10] or "0"
    local mountsStr = remaining[11] or ""



    local items = ParseItemList(itemsStr)
    local hiddenSlots = ParseHiddenList(hiddenStr, items)

    local loadout = {
        name = UnescapeName(name),
        items = items,
        hiddenSlots = hiddenSlots,
        enchantMH = tonumber(emh) or 0,
        enchantOH = tonumber(eoh) or 0,
        mountDisplay = tonumber(mount) or 0,
        mountHidden = mhidden == "1",
        petDisplay = tonumber(pet) or 0,
        combatPetDisplay = tonumber(hpet) or 0,
        combatPetScale = (tonumber(hpscale100) or 100) / 100.0,
        morphForm = tonumber(morph) or 0,
        morphScale = (tonumber(mscale100) or 100) / 100.0,
        titleID = tonumber(title) or 0,
        mounts = ParseMountsList(mountsStr),
    }

    if loadout.enchantMH <= 0 then loadout.enchantMH = nil end
    if loadout.enchantOH <= 0 then loadout.enchantOH = nil end
    if loadout.mountDisplay <= 0 then loadout.mountDisplay = nil end
    if loadout.petDisplay <= 0 then loadout.petDisplay = nil end
    if loadout.combatPetDisplay <= 0 then
        loadout.combatPetDisplay = nil
        loadout.combatPetScale = nil
    end
    if loadout.morphForm <= 0 then
        loadout.morphForm = nil
        loadout.morphScale = nil
    end
    if loadout.titleID <= 0 then loadout.titleID = nil end

    return loadout, nil
end

function ns.IsLoadoutExportString(encoded)
    if type(encoded) ~= "string" then return false end
    encoded = encoded:match("^%s*(.-)%s*$")
    return encoded:sub(1, #FORMAT_TAG) == FORMAT_TAG
        and (encoded:sub(#FORMAT_TAG + 1, #FORMAT_TAG + 1) == "|")
end
