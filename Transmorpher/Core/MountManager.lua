local addon, ns = ...

-- ============================================================
-- MOUNT MANAGER
-- Centralized system for mount detection, flight status,
-- and perfected morph application.
-- ============================================================

ns.MountManager = {}
local MM = ns.MountManager

-- ============================================================
-- LOGGING
-- ============================================================
local function TMLog(msg)
    if not msg then return end
    local timestamp = date("%H:%M:%S")
    local logLine = "[" .. timestamp .. "] [MountMgr] " .. msg
    if TRANSMORPHER_LOG then
        TRANSMORPHER_LOG = TRANSMORPHER_LOG .. "\n" .. logLine
    end
    -- Also print to chat for easy in-game debugging if needed
    -- print("|cffF5C842<TM-Deb>|r " .. msg)
end

-- Variables for tracking
MM.lastMountedState = false

-- ============================================================
-- MOUNT IDENTIFICATION HELPER
-- ============================================================

function MM.GetActiveMountSpellID()
    if not IsMounted() then return nil end
    
    -- Check ALL helpful buffs to find a mount spell
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        
        -- Efficient check using the lookup table
        if ns.mountSpellLookup and ns.mountSpellLookup[spellID] then
            return spellID
        end
    end
    
    return nil
end

-- ============================================================
-- MORPH APPLICATION
-- Determines the correct morph and pushes it to the DLL.
-- ============================================================

function MM.GetTargetDisplayID(forcedSpellID)
    if not TransmorpherCharacterState then return nil end
    local state = TransmorpherCharacterState

    -- Global Hide toggle
    if state.MountHidden then return -1 end

    -- 1. Per-mount specific morph (Highest priority)
    local activeSpellID = forcedSpellID or MM.GetActiveMountSpellID()
    if activeSpellID and state.Mounts and state.Mounts[activeSpellID] then
        TMLog("Using per-mount morph: " .. state.Mounts[activeSpellID])
        return state.Mounts[activeSpellID]
    end

    -- 2. Universal Mount Morph
    return state.MountDisplay
end

function MM.ApplyCorrectMorph(isMounting, forcedSpellID)
    if not ns.IsMorpherReady() then return end
    
    local targetID = MM.GetTargetDisplayID(forcedSpellID) or 0
    
    if targetID == 0 then
        TMLog("Resetting mount morph (none assigned)")
        ns.SendRawMorphCommand("MOUNT_RESET")
        return
    end

    -- Single shot application
    TMLog("Applying mount morph: " .. targetID)
    ns.SendRawMorphCommand("MOUNT_MORPH:" .. targetID)
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================

MM.eventFrame = CreateFrame("Frame")
MM.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
MM.eventFrame:RegisterEvent("UNIT_MODEL_CHANGED")
MM.eventFrame:RegisterEvent("SPELLS_CHANGED")
MM.eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
MM.eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")

MM.eventFrame:SetScript("OnEvent", function(self, event, ...)
    local unit = ...
    
    if event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
        -- Safety: avoid hitting the DLL immediately on load
        ns.TimerAfter(0.7, function()
            MM.ApplyCorrectMorph(false)
        end)
    end

    if not TransmorpherCharacterState then return end

    -- 1. Pre-emptive Cast Detection (Mounting Start)
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SENT" then
        if unit == "player" then
            local _, _, _, _, _, _, _, _, spellID = UnitCastingInfo("player")
            if not spellID and event == "UNIT_SPELLCAST_SENT" then
                 _, _, _, spellID = ...
            end
            
            if spellID and ns.mountSpellLookup and ns.mountSpellLookup[spellID] then
                TMLog("Mount cast detected: " .. spellID .. ". Starting burst.")
                MM.ApplyCorrectMorph(true, spellID) 
            end
        end
        return
    end

    -- 2. Mount/Dismount Detection (Consistency)
    local currentMounted = IsMounted()
    if currentMounted ~= MM.lastMountedState then
        TMLog("Mount state change: " .. tostring(MM.lastMountedState) .. " -> " .. tostring(currentMounted))
        MM.lastMountedState = currentMounted
        if currentMounted then
            -- Trigger a fresh burst when the mount state actually switches to true
            MM.ApplyCorrectMorph(true)
        end
    elseif currentMounted and event == "UNIT_MODEL_CHANGED" and unit == "player" then
        -- Safety Refresh: If the model is forced to change while already mounted.
        -- Throttle to once every 2 seconds to avoid Error 132 during rapid transitions.
        local now = GetTime()
        MM.lastModelRefresh = MM.lastModelRefresh or 0
        if (now - MM.lastModelRefresh) > 2.0 then
            MM.lastModelRefresh = now
            TMLog("Safety refresh triggered for player model change while mounted.")
            MM.ApplyCorrectMorph(false)
        end
    end
end)
