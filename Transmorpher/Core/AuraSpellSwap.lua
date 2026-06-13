local addon, ns = ...

-- ============================================================
-- SPELLSWAP BY AURA ENGINE (ROBUST VERSION)
-- Fully deterministic state machine with no leaks
-- ============================================================

ns.activeAuraSwapRules = ns.activeAuraSwapRules or {}
ns.auraSwapOriginalMorphs = ns.auraSwapOriginalMorphs or {}
ns.auraSwapOwnership = ns.auraSwapOwnership or {}
ns.pendingDeactivations = ns.pendingDeactivations or {}
ns.auraSwapActiveSourceIds = ns.auraSwapActiveSourceIds or {}
ns.auraSwapProcessing = false -- Prevent recursive calls

local function NotifyAuraSwapUI()
    if type(ns.NotifyAuraSpellSwapStateChanged) == "function" then
        ns.NotifyAuraSpellSwapStateChanged()
    end
end

local function EnsureRuleStore()
    if not TransmorpherCharacterState then return nil end
    if not TransmorpherCharacterState.AuraSpellSwapRules then
        TransmorpherCharacterState.AuraSpellSwapRules = {}
    end
    return TransmorpherCharacterState.AuraSpellSwapRules
end

local function QueueVisualPatch(sourceSpellId, targetSpellId)
    sourceSpellId = tonumber(sourceSpellId)
    targetSpellId = tonumber(targetSpellId)
    if sourceSpellId and sourceSpellId > 0 and targetSpellId and targetSpellId > 0 then
        ns.SendRawMorphCommand("SPELL_VISUAL_PATCH:" .. sourceSpellId .. ":" .. targetSpellId)
    end
end

local function QueueVisualRestore(sourceSpellId)
    sourceSpellId = tonumber(sourceSpellId)
    if sourceSpellId and sourceSpellId > 0 then
        ns.SendRawMorphCommand("SPELL_VISUAL_RESTORE:" .. sourceSpellId)
    end
end

-- Immediate revert - no waiting
local function ImmediateRevertSource(sourceId, originalMorph, ownerUid)
    if not sourceId then return end
    
    sourceId = tonumber(sourceId)
    if not sourceId or sourceId <= 0 then return end
    
    -- Clear runtime morph FIRST (this is the aura swap override)
    ns.ClearRuntimeSpellMorph(sourceId)
    
    -- Send visual restore IMMEDIATELY to clear any visual artifacts
    QueueVisualRestore(sourceId)
    
    -- Restore to base morph or clear
    if originalMorph and originalMorph ~= false then
        ns.SetSpellMorph(sourceId, originalMorph)
        ns.SendMorphCommand("SPELL_MORPH:" .. sourceId .. ":" .. originalMorph)
    else
        ns.SetSpellMorph(sourceId, nil)
        ns.SendMorphCommand("SPELL_RESET:" .. sourceId)
    end
    
    -- Clean up ownership
    if ns.auraSwapOwnership[sourceId] == ownerUid then
        ns.auraSwapOwnership[sourceId] = nil
    end
    
    ns.auraSwapOriginalMorphs[sourceId] = nil
    ns.auraSwapActiveSourceIds[sourceId] = nil
end

-- Apply aura swap immediately
local function ImmediateApplySource(sourceId, targetId, uid)
    if not sourceId or not targetId then return end
    
    sourceId = tonumber(sourceId)
    targetId = tonumber(targetId)
    if not sourceId or sourceId <= 0 or not targetId or targetId <= 0 then return end
    
    -- Store the ORIGINAL morph BEFORE we override
    local existingBaseMorph = ns.GetBaseSpellMorph(sourceId)
    ns.auraSwapOriginalMorphs[sourceId] = existingBaseMorph or false
    ns.auraSwapOwnership[sourceId] = uid
    ns.auraSwapActiveSourceIds[sourceId] = true
    
    -- Apply RUNTIME morph (takes precedence)
    ns.SetRuntimeSpellMorph(sourceId, targetId)
    ns.SendMorphCommand("SPELL_MORPH:" .. sourceId .. ":" .. targetId)
    
    -- Apply visual patch
    QueueVisualPatch(sourceId, targetId)
end

function ns.GetAuraSpellSwapRules()
    local store = EnsureRuleStore()
    return store or {}
end

function ns.SaveAuraSpellSwapRule(uid, rule)
    if not uid or uid == "" or type(rule) ~= "table" then return end
    local store = EnsureRuleStore()
    if not store then return end
    store[uid] = rule
    
    -- If rule was just disabled, revert it immediately
    if rule.enabled == false then
        ns.RevertAuraSwapRule(uid)
    end
    
    NotifyAuraSwapUI()
end

function ns.DeleteAuraSpellSwapRule(uid)
    local store = EnsureRuleStore()
    if not store then return end

    local rule = store[uid]
    if rule and rule.swaps then
        for _, swap in ipairs(rule.swaps) do
            local sourceId = tonumber(swap.source)
            if sourceId and sourceId > 0 and ns.auraSwapOwnership[sourceId] == uid then
                local originalMorph = ns.auraSwapOriginalMorphs[sourceId]
                ImmediateRevertSource(sourceId, originalMorph, uid)
            end
        end
    end

    ns.activeAuraSwapRules[uid] = nil
    ns.pendingDeactivations[uid] = nil
    store[uid] = nil
    
    NotifyAuraSwapUI()
end

function ns.GenerateRuleUID()
    return tostring(GetTime()):gsub("%.", "") .. tostring(math.random(1000, 9999))
end

function ns.ApplyAuraSwapRule(uid)
    if ns.auraSwapProcessing then return end
    ns.auraSwapProcessing = true
    
    local rules = ns.GetAuraSpellSwapRules()
    local rule = rules[uid]
    if not rule or not rule.enabled or not rule.swaps then 
        ns.auraSwapProcessing = false
        return 
    end
    if ns.activeAuraSwapRules[uid] then 
        ns.auraSwapProcessing = false
        return 
    end

    ns.activeAuraSwapRules[uid] = true

    for _, swap in ipairs(rule.swaps) do
        local sourceId = tonumber(swap.source)
        local targetId = tonumber(swap.target)
        if sourceId and sourceId > 0 and targetId and targetId > 0 then
            -- Only take ownership if not already owned by another active rule
            if not ns.auraSwapOwnership[sourceId] then
                ImmediateApplySource(sourceId, targetId, uid)
            end
        end
    end

    ns.auraSwapProcessing = false
    NotifyAuraSwapUI()
end

function ns.RevertAuraSwapRule(uid)
    if ns.auraSwapProcessing then return end
    ns.auraSwapProcessing = true
    
    local rules = ns.GetAuraSpellSwapRules()
    local rule = rules[uid]
    if not rule or not rule.swaps then 
        ns.auraSwapProcessing = false
        return 
    end
    if not ns.activeAuraSwapRules[uid] then 
        ns.auraSwapProcessing = false
        return 
    end

    ns.activeAuraSwapRules[uid] = nil
    ns.pendingDeactivations[uid] = nil

    for _, swap in ipairs(rule.swaps) do
        local sourceId = tonumber(swap.source)
        if sourceId and sourceId > 0 and ns.auraSwapOwnership[sourceId] == uid then
            local originalMorph = ns.auraSwapOriginalMorphs[sourceId]
            ImmediateRevertSource(sourceId, originalMorph, uid)
        end
    end

    ns.auraSwapProcessing = false
    NotifyAuraSwapUI()
end

local function BuildAuraLookup()
    local lookup = {}
    for uid, rule in pairs(ns.GetAuraSpellSwapRules()) do
        if rule.enabled and rule.auraSpellId then
            local auraId = tonumber(rule.auraSpellId)
            if auraId and auraId > 0 then
                lookup[auraId] = lookup[auraId] or {}
                table.insert(lookup[auraId], uid)
            end
        end
    end
    return lookup
end

-- Full cleanup of ALL state - used for debugging or hard reset
local function FullCleanup()
    -- Revert all active rules first
    for uid in pairs(ns.activeAuraSwapRules) do
        ns.RevertAuraSwapRule(uid)
    end
    
    -- Force clear any remaining ownership
    for sourceId in pairs(ns.auraSwapOwnership) do
        local originalMorph = ns.auraSwapOriginalMorphs[sourceId]
        ImmediateRevertSource(sourceId, originalMorph, ns.auraSwapOwnership[sourceId])
    end
    
    wipe(ns.activeAuraSwapRules)
    wipe(ns.auraSwapOriginalMorphs)
    wipe(ns.auraSwapOwnership)
    wipe(ns.pendingDeactivations)
    wipe(ns.auraSwapActiveSourceIds)
end

function ns.CheckAuraSpellSwaps()
    if ns.auraSwapProcessing then return end
    ns.auraSwapProcessing = true
    
    local rules = ns.GetAuraSpellSwapRules()
    
    -- If no rules, clean up everything
    if not rules or not next(rules) then
        FullCleanup()
        ns.auraSwapProcessing = false
        NotifyAuraSwapUI()
        return
    end

    local auraLookup = BuildAuraLookup()
    if not next(auraLookup) then
        FullCleanup()
        ns.auraSwapProcessing = false
        NotifyAuraSwapUI()
        return
    end

    -- Get current active auras on player
    local activeAuraIds = {}
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HELPFUL")
        if not spellID then break end
        activeAuraIds[spellID] = true
    end
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura("player", i, "HARMFUL")
        if not spellID then break end
        activeAuraIds[spellID] = true
    end

    -- Determine which rules should be active based on current auras
    local rulesNowActive = {}
    for auraId, ruleUIDs in pairs(auraLookup) do
        if activeAuraIds[auraId] then
            for _, uid in ipairs(ruleUIDs) do
                rulesNowActive[uid] = true
            end
        end
    end

    -- DEACTIVATE: Rules that were active but aura is no longer present
    local toDeactivate = {}
    for uid in pairs(ns.activeAuraSwapRules) do
        if not rulesNowActive[uid] then
            table.insert(toDeactivate, uid)
        end
    end
    
    -- Process deactivations first
    for _, uid in ipairs(toDeactivate) do
        if ns.activeAuraSwapRules[uid] then
            local rule = rules[uid]
            if rule and rule.swaps then
                for _, swap in ipairs(rule.swaps) do
                    local sourceId = tonumber(swap.source)
                    if sourceId and sourceId > 0 and ns.auraSwapOwnership[sourceId] == uid then
                        local originalMorph = ns.auraSwapOriginalMorphs[sourceId]
                        ImmediateRevertSource(sourceId, originalMorph, uid)
                    end
                end
            end
            ns.activeAuraSwapRules[uid] = nil
        end
    end

    -- ACTIVATE: Rules that should be active but aren't yet
    for uid in pairs(rulesNowActive) do
        if not ns.activeAuraSwapRules[uid] then
            local rule = rules[uid]
            if rule and rule.enabled and rule.swaps then
                for _, swap in ipairs(rule.swaps) do
                    local sourceId = tonumber(swap.source)
                    local targetId = tonumber(swap.target)
                    if sourceId and sourceId > 0 and targetId and targetId > 0 then
                        -- Only take ownership if free
                        if not ns.auraSwapOwnership[sourceId] then
                            ImmediateApplySource(sourceId, targetId, uid)
                        end
                    end
                end
                ns.activeAuraSwapRules[uid] = true
            end
        end
    end
    
    -- ORPHAN CLEANUP: Clear ownership for source IDs that don't belong to active rules
    local activeRuleSet = {}
    for uid in pairs(ns.activeAuraSwapRules) do
        activeRuleSet[uid] = true
    end
    
    for sourceId, ownerUid in pairs(ns.auraSwapOwnership) do
        if not activeRuleSet[ownerUid] then
            local originalMorph = ns.auraSwapOriginalMorphs[sourceId]
            ImmediateRevertSource(sourceId, originalMorph, ownerUid)
        end
    end

    ns.auraSwapProcessing = false
    NotifyAuraSwapUI()
end

function ns.ScheduleAuraSpellSwapCheck()
    ns.CheckAuraSpellSwaps()
end

-- Force reset all aura swap state (call on logout/character switch)
function ns.ForceResetAuraSwaps()
    FullCleanup()
    NotifyAuraSwapUI()
end

-- Periodic self-healing check to catch any stuck states
local function StartPeriodicVerification()
    local verifyFrame = CreateFrame("Frame")
    verifyFrame.elapsed = 0
    verifyFrame.verifyInterval = 5.0 -- Verify every 5 seconds
    verifyFrame:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= self.verifyInterval then
            self.elapsed = 0
            -- Run a verification check without triggering full revert
            ns.CheckAuraSpellSwaps()
        end
    end)
end

function ns.InitAuraSpellSwaps()
    if not TransmorpherCharacterState then return end
    EnsureRuleStore()

    -- Full cleanup before initialization
    FullCleanup()

    local initFrame = CreateFrame("Frame")
    initFrame.elapsed = 0
    initFrame:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 1.0 then
            self:SetScript("OnUpdate", nil)
            ns.CheckAuraSpellSwaps()
            -- Start periodic verification after initial check
            StartPeriodicVerification()
        end
    end)

    NotifyAuraSwapUI()
end

-- Debug function to check state
function ns.DebugAuraSwapState()
    print("=== Aura Swap Debug ===")
    print("Active Rules:")
    for uid in pairs(ns.activeAuraSwapRules) do
        print("  - " .. uid)
    end
    print("Ownership:")
    for sourceId, owner in pairs(ns.auraSwapOwnership) do
        print("  Source " .. sourceId .. " owned by " .. owner)
    end
    print("Original Morphs:")
    for sourceId, orig in pairs(ns.auraSwapOriginalMorphs) do
        print("  Source " .. sourceId .. " -> " .. tostring(orig))
    end
    print("Runtime Morphs:")
    if ns.runtimeSpellMorphs then
        for sourceId, target in pairs(ns.runtimeSpellMorphs) do
            print("  Source " .. sourceId .. " -> " .. target)
        end
    end
    print("======================")
end
