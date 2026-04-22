local addon, ns = ...

local ENV_DEFAULTS = {
    worldFogEnabled = false,
    worldFogColor = "#AAAAAA",
    worldFogStart = 500,
    worldFogEnd = 2500,
    worldFarClipEnabled = false,
    worldFarClip = 2666,
}

local ENV_SETTING_ALIASES = {
    worldFogEnabled = "espWorldFogEnabled",
    worldFogColor = "espWorldFogColor",
    worldFogStart = "espWorldFogStart",
    worldFogEnd = "espWorldFogEnd",
}

local function getSettings()
    return ns.GetSettings()
end

local function resolveEnvironmentSettingKey(settingKey)
    return ENV_SETTING_ALIASES[settingKey] or settingKey
end

local function copyAliasValue(settings, settingKey)
    local aliasKey = ENV_SETTING_ALIASES[settingKey]
    if not aliasKey then return end

    if settings[settingKey] == nil and settings[aliasKey] ~= nil then
        settings[settingKey] = settings[aliasKey]
    elseif settings[aliasKey] == nil and settings[settingKey] ~= nil then
        settings[aliasKey] = settings[settingKey]
    end
end

local function getCurrentClientFarClip()
    if type(GetCVar) == "function" then
        local value = tonumber(GetCVar("farclip"))
        if value and value >= 100 and value <= 2666 then
            return value
        end
    end

    return ENV_DEFAULTS.worldFarClip
end

function ns.GetWorldEnvironmentSettings()
    local settings = getSettings()

    copyAliasValue(settings, "worldFogEnabled")
    copyAliasValue(settings, "worldFogColor")
    copyAliasValue(settings, "worldFogStart")
    copyAliasValue(settings, "worldFogEnd")

    if settings.worldFogEnabled == nil then settings.worldFogEnabled = ENV_DEFAULTS.worldFogEnabled end
    if not tostring(settings.worldFogColor or ""):match("^#%x%x%x%x%x%x$") then
        settings.worldFogColor = ENV_DEFAULTS.worldFogColor
    end
    settings.worldFogColor = tostring(settings.worldFogColor):upper()
    settings.worldFogStart = tonumber(settings.worldFogStart) or ENV_DEFAULTS.worldFogStart
    settings.worldFogEnd = tonumber(settings.worldFogEnd) or ENV_DEFAULTS.worldFogEnd
    settings.worldFarClipEnabled = settings.worldFarClipEnabled and true or false
    settings.worldFarClip = tonumber(settings.worldFarClip) or ENV_DEFAULTS.worldFarClip

    if settings.worldFogStart < 0 then settings.worldFogStart = 0 end
    if settings.worldFogStart > 4000 then settings.worldFogStart = 4000 end
    if settings.worldFogEnd < settings.worldFogStart + 10 then settings.worldFogEnd = settings.worldFogStart + 10 end
    if settings.worldFogEnd > 6000 then settings.worldFogEnd = 6000 end
    if settings.worldFarClip < 100 then settings.worldFarClip = 100 end
    if settings.worldFarClip > 2666 then settings.worldFarClip = 2666 end

    settings[resolveEnvironmentSettingKey("worldFogEnabled")] = settings.worldFogEnabled
    settings[resolveEnvironmentSettingKey("worldFogColor")] = settings.worldFogColor
    settings[resolveEnvironmentSettingKey("worldFogStart")] = settings.worldFogStart
    settings[resolveEnvironmentSettingKey("worldFogEnd")] = settings.worldFogEnd

    return settings
end

function ns.SetWorldEnvironmentSetting(settingKey, value)
    local settings = ns.GetWorldEnvironmentSettings()
    settings[settingKey] = value

    local aliasKey = ENV_SETTING_ALIASES[settingKey]
    if aliasKey then
        settings[aliasKey] = value
    end
end

function ns.ResetWorldFogSettings()
    ns.SetWorldEnvironmentSetting("worldFogEnabled", ENV_DEFAULTS.worldFogEnabled)
    ns.SetWorldEnvironmentSetting("worldFogColor", ENV_DEFAULTS.worldFogColor)
    ns.SetWorldEnvironmentSetting("worldFogStart", ENV_DEFAULTS.worldFogStart)
    ns.SetWorldEnvironmentSetting("worldFogEnd", ENV_DEFAULTS.worldFogEnd)
    ns.QueueWorldEnvironmentSync()
end

function ns.ResetWorldAtmosphereSettings()
    ns.SetWorldEnvironmentSetting("worldFarClipEnabled", ENV_DEFAULTS.worldFarClipEnabled)
    ns.SetWorldEnvironmentSetting("worldFarClip", getCurrentClientFarClip())
    ns.QueueWorldEnvironmentSync()
end

function ns.QueueWorldEnvironmentSync()
    if not ns.IsMorpherReady or not ns.IsMorpherReady() then return end

    local settings = ns.GetWorldEnvironmentSettings()
    local payload = {
        "worldfog=" .. (settings.worldFogEnabled and "1" or "0"),
        "worldfogcolor=" .. tostring(settings.worldFogColor):gsub("^#", ""),
        "worldfogstart=" .. string.format("%.3f", tonumber(settings.worldFogStart) or ENV_DEFAULTS.worldFogStart),
        "worldfogend=" .. string.format("%.3f", tonumber(settings.worldFogEnd) or ENV_DEFAULTS.worldFogEnd),
        "worldfarclipenabled=" .. (settings.worldFarClipEnabled and "1" or "0"),
        "worldfarclip=" .. string.format("%.3f", tonumber(settings.worldFarClip) or ENV_DEFAULTS.worldFarClip),
    }

    TRANSMORPHER_ENV_CFG = table.concat(payload, ";")
end

local environmentReadyWatcher = CreateFrame("Frame")
environmentReadyWatcher.lastReady = false
environmentReadyWatcher:SetScript("OnUpdate", function(self)
    local ready = ns.IsMorpherReady and ns.IsMorpherReady()
    if ready and not self.lastReady then
        ns.QueueWorldEnvironmentSync()
    end
    self.lastReady = ready and true or false
end)
