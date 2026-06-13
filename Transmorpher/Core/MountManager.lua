local addon, ns = ...

-- ============================================================
-- MOUNT MANAGER — Spell detection, display ID resolution
-- and DLL communication for mount morphing.
-- ============================================================

local function GetActiveMountSpellID()
    if not IsMounted() then return nil end
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        if ns.mountSpellLookup and ns.mountSpellLookup[spellID] then
            return spellID
        end
    end
    return nil
end

local function GetTargetMountDisplayID()
    if not TransmorpherCharacterState then return nil end
    local state = TransmorpherCharacterState
    
    -- "Hide Mount" support: return -1 to indicate invisibility to the DLL
    if state.MountHidden then return -1 end
    return state.MountDisplay
end

local lastSentTargetID = nil
local lastApplyTime = 0
local MOUNT_DEBOUNCE_MS = 0.1 -- 100ms debounce

local function ApplyMountMorph(isMounting)
    if not ns.IsMorpherReady() or ns.vehicleSuspended then return end
    
    -- Debounce: prevent rapid re-application during transitions
    local now = GetTime()
    if (now - lastApplyTime) < MOUNT_DEBOUNCE_MS and not isMounting then return end
    lastApplyTime = now
    
    local targetID = GetTargetMountDisplayID() or 0
    
    -- 1. Pre-emptive signaling: Always tell the DLL we are entering 'mounted' state
    -- This ensures Layer 2 (Visual Hook) is ready to enforce the model.
    if (IsMounted() or isMounting) and not UnitInVehicle("player") then
        ns.SendRawMorphCommand("SET:MOUNTED:1")
    end

    if targetID == 0 then
        -- No morph assigned: ensure DLL goes back to native
        if lastSentTargetID ~= 0 then
            ns.SendRawMorphCommand("MOUNT_RESET")
            lastSentTargetID = 0
        end
    else
        -- 2. Apply the actual morph ONLY if it changed since last command.
        -- This prevents redundant descriptor writes while allowing the DLL 
        -- to maintain its internal persistent state.
        if targetID ~= lastSentTargetID then
            ns.SendRawMorphCommand("MOUNT_MORPH:" .. targetID)
            lastSentTargetID = targetID
        end
    end
end

-- Reset last sent ID on zone change so mount morph is re-sent after teleport
local function ResetForZoneChange()
    lastSentTargetID = nil
    lastApplyTime = 0
end

-- Export to namespace
ns.MountManager = {
    GetActiveMountSpellID = GetActiveMountSpellID,
    GetTargetDisplayID = GetTargetMountDisplayID,
    ApplyCorrectMorph = ApplyMountMorph,
    ResetForZoneChange = ResetForZoneChange,
}
