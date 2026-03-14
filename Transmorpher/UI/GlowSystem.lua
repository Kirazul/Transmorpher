local addon, ns = ...

-- ============================================================
-- RETAIL-STYLE SLOT GLOW SYSTEM
-- Pro-level multi-layer animation using transmog-specific textures
-- Layers: 1. Inner Pulse | 2. Main Border (Breathing) | 3. Outer Halo
-- ============================================================

local GLOW_TEXTURE = "Interface\\AddOns\\Transmorpher\\Textures\\transmog_border"
local HALO_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- Refined color palette for high-end look
local glowColors = {
    gold   = { inner={1.0, 0.82, 0.40}, border={1.0, 0.75, 0.10}, outer={1.0, 0.60, 0.0} },
    purple = { inner={0.80, 0.50, 1.00}, border={0.65, 0.25, 0.95}, outer={0.50, 0.10, 0.85} },
    blue   = { inner={0.40, 0.70, 1.00}, border={0.10, 0.50, 1.00}, outer={0.00, 0.30, 0.90} },
    green  = { inner={0.50, 1.00, 0.50}, border={0.15, 0.90, 0.15}, outer={0.05, 0.75, 0.05} },
    red    = { inner={1.00, 0.40, 0.40}, border={0.90, 0.10, 0.10}, outer={0.75, 0.00, 0.00} },
}

local morphGlowAnimFrame = CreateFrame("Frame")
morphGlowAnimFrame:Hide()
local morphGlowSlots = {}
local morphGlowTimer = 0

morphGlowAnimFrame:SetScript("OnUpdate", function(self, dt)
    morphGlowTimer = morphGlowTimer + dt

    -- Sync animations with different frequencies for "alive" feel
    local pulseFast = 0.5 + 0.5 * math.sin(morphGlowTimer * 5.0)
    local pulseSlow = 0.6 + 0.4 * math.sin(morphGlowTimer * 2.8)
    local shimmer = 0.4 + 0.3 * math.cos(morphGlowTimer * 7.0)

    for slot, layers in pairs(morphGlowSlots) do
        if layers.inner and layers.inner:IsShown() then
            -- Fade-in multiplier (0→1 over 0.3s)
            local fadeMul = 1
            if layers.fadeInElapsed then
                layers.fadeInElapsed = layers.fadeInElapsed + dt
                if layers.fadeInElapsed < 0.3 then
                    fadeMul = layers.fadeInElapsed / 0.3
                else
                    layers.fadeInElapsed = nil
                end
            end

            -- Layer 1: Subtle inner shimmer (Boosted)
            layers.inner:SetAlpha((0.15 + 0.15 * shimmer) * fadeMul)

            -- Layer 2: Main Border Breathing (Strong peak)
            layers.border:SetAlpha((0.70 + 0.30 * pulseSlow) * fadeMul)

            -- Layer 3: Outer Halo Pulse (Much stronger "Bloom" effect)
            layers.outer:SetAlpha((0.40 + 0.50 * pulseFast) * fadeMul)

            -- Confirmation flash fade-out
            if layers.flash and layers.flashElapsed then
                layers.flashElapsed = layers.flashElapsed + dt
                
                -- Flash hold/fade durations
                local holdTime = 1.0
                local fadeTime = 0.8
                
                if layers.flashElapsed < holdTime then
                    -- Keep it pure white and bright
                    layers.flash:SetAlpha(0.9)
                    layers.border:SetVertexColor(1, 1, 1)
                    layers.outer:SetVertexColor(1, 1, 1)
                elseif layers.flashElapsed < (holdTime + fadeTime) then
                    -- Smooth transition back to color
                    local progress = (layers.flashElapsed - holdTime) / fadeTime
                    local flashAlpha = math.max(0, 0.9 * (1 - progress))
                    layers.flash:SetAlpha(flashAlpha)
                    
                    local color = glowColors[slot.glowColorType or "gold"] or glowColors.gold
                    -- Linear interpolation from white to target color
                    local r = 1 + (color.border[1] - 1) * progress
                    local g = 1 + (color.border[2] - 1) * progress
                    local b = 1 + (color.border[3] - 1) * progress
                    layers.border:SetVertexColor(r, g, b)
                    
                    local or_ = 1 + (color.outer[1] - 1) * progress
                    local og = 1 + (color.outer[2] - 1) * progress
                    local ob = 1 + (color.outer[3] - 1) * progress
                    layers.outer:SetVertexColor(or_, og, ob)
                else
                    -- Animation finished
                    layers.flash:Hide()
                    layers.flashElapsed = nil
                    local color = glowColors[slot.glowColorType or "gold"] or glowColors.gold
                    layers.border:SetVertexColor(color.border[1], color.border[2], color.border[3])
                    layers.outer:SetVertexColor(color.outer[1], color.outer[2], color.outer[3])
                end
            end
        end
    end
end)

local function AddMorphGlow(slot, colorType)
    if slot.morphGlowLayers then return slot.morphGlowLayers end
    local layers = {}
    local color = glowColors[colorType] or glowColors.gold

    -- Layer 1: Inner Overlay (Boosted base)
    local inner = slot:CreateTexture(nil, "OVERLAY", nil, 1)
    inner:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
    inner:SetTexture(WHITE_TEXTURE)
    inner:SetBlendMode("ADD")
    inner:SetVertexColor(color.inner[1], color.inner[2], color.inner[3], 0.25)
    inner:Hide()
    layers.inner = inner

    -- Layer 2: Main Transmog Border (Stronger base)
    local border = slot:CreateTexture(nil, "OVERLAY", nil, 2)
    border:SetPoint("TOPLEFT", slot, "TOPLEFT", -12, 12)
    border:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 12, -12)
    border:SetTexture(GLOW_TEXTURE)
    border:SetBlendMode("ADD")
    border:SetVertexColor(color.border[1], color.border[2], color.border[3], 1.0)
    border:Hide()
    layers.border = border

    -- Layer 3: Outer Halo (Stronger peak bloom)
    local outer = slot:CreateTexture(nil, "OVERLAY", nil, 3)
    outer:SetPoint("TOPLEFT", slot, "TOPLEFT", -18, 18)
    outer:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 18, -18)
    outer:SetTexture(HALO_TEXTURE)
    outer:SetBlendMode("ADD")
    outer:SetVertexColor(color.outer[1], color.outer[2], color.outer[3], 0.65)
    outer:Hide()
    layers.outer = outer

    slot.morphGlowLayers = layers
    slot.glowColorType = colorType or "gold"
    return layers
end

function ns.ShowMorphGlow(slot, colorType)
    if not slot then return end
    local layers = AddMorphGlow(slot, colorType)
    
    -- Update colors if type changed
    local color = glowColors[colorType] or glowColors.gold
    layers.inner:SetVertexColor(color.inner[1], color.inner[2], color.inner[3])
    layers.border:SetVertexColor(color.border[1], color.border[2], color.border[3])
    layers.outer:SetVertexColor(color.outer[1], color.outer[2], color.outer[3])

    layers.inner:Show()
    layers.border:Show()
    layers.outer:Show()
    layers.fadeInElapsed = 0
    morphGlowSlots[slot] = layers
    morphGlowAnimFrame:Show()
end

function ns.HideMorphGlow(slot)
    if not slot then return end
    if slot.morphGlowLayers then
        slot.morphGlowLayers.inner:Hide()
        slot.morphGlowLayers.border:Hide()
        slot.morphGlowLayers.outer:Hide()
    end
    morphGlowSlots[slot] = nil
    
    local hasAny = false
    for _ in pairs(morphGlowSlots) do hasAny = true; break end
    if not hasAny then morphGlowAnimFrame:Hide() end
end

-- Confirmation flash: white burst then settle to gold glow
function ns.FlashMorphSlot(slot, colorType)
    if not slot then return end
    ns.ShowMorphGlow(slot, colorType)
    local layers = slot.morphGlowLayers
    if not layers then return end
    if not layers.flash then
        local flash = slot:CreateTexture(nil, "OVERLAY", nil, 4)
        flash:SetPoint("TOPLEFT", slot, "TOPLEFT", -14, 14)
        flash:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 14, -14)
        flash:SetTexture(GLOW_TEXTURE)
        flash:SetBlendMode("ADD")
        flash:Hide()
        layers.flash = flash
    end
    layers.flash:SetVertexColor(1, 1, 1)
    layers.flash:SetAlpha(0.9)
    layers.flash:Show()
    layers.flashElapsed = 0
    layers.border:SetVertexColor(1, 1, 1)
    layers.outer:SetVertexColor(1, 1, 1)
end
