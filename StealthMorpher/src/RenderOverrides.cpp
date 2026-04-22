#include "RenderOverrides.h"

#include "ShutdownCheck.h"

#include <cmath>
#include <cstring>

extern "C" volatile bool g_isProcessTerminating;

namespace {

static const DWORD ADDR_WORLD_FARCLIP = 0x00CD7748;
static const float kDefaultSmoothTextureBias = 1.25f;

enum SamplerStateIndex {
    SAMPLER_STATE_MIN = 0,
    SAMPLER_STATE_MAG,
    SAMPLER_STATE_MIP,
    SAMPLER_STATE_LOD_BIAS,
    SAMPLER_STATE_COUNT,
};

struct NativeFogState {
    bool hasEnable;
    bool hasColor;
    bool hasStart;
    bool hasEnd;
    bool hasTableMode;
    bool hasVertexMode;
    bool hasRange;
    DWORD enable;
    DWORD color;
    DWORD start;
    DWORD end;
    DWORD tableMode;
    DWORD vertexMode;
    DWORD range;
};

struct NativeSamplerState {
    bool valid[16][SAMPLER_STATE_COUNT];
    DWORD value[16][SAMPLER_STATE_COUNT];
};

static CRITICAL_SECTION g_lock;
static bool g_lockReady = false;
static RenderOverrideConfig g_config = {};
static bool g_worldOriginalFarClipCaptured = false;
static float g_worldOriginalFarClip = 777.0f;
static NativeFogState g_nativeFogState = {};
static NativeSamplerState g_nativeSamplerState = {};

static float ClampFogStartValue(float value) {
    if (value < 0.0f) return 0.0f;
    if (value > 5000.0f) return 5000.0f;
    return value;
}

static float ClampFogEndValue(float value) {
    if (value < 1.0f) return 1.0f;
    if (value > 6000.0f) return 6000.0f;
    return value;
}

static float ClampFarClip(float value) {
    if (value < 100.0f) return 100.0f;
    if (value > 2666.0f) return 2666.0f;
    return value;
}

static float ClampSmoothTextureBias(float value) {
    if (!_finite(value)) return kDefaultSmoothTextureBias;
    if (value < 0.0f) return 0.0f;
    if (value > 10.0f) return 10.0f;
    return value;
}

static float GetSafeFarClip(float value) {
    if (!_finite(value) || value < 100.0f || value > 12000.0f) {
        return 777.0f;
    }
    return value;
}

static DWORD FloatToDword(float value) {
    DWORD bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    return bits;
}

static int GetTrackedSamplerStateIndex(D3DSAMPLERSTATETYPE type) {
    switch (type) {
    case D3DSAMP_MINFILTER: return SAMPLER_STATE_MIN;
    case D3DSAMP_MAGFILTER: return SAMPLER_STATE_MAG;
    case D3DSAMP_MIPFILTER: return SAMPLER_STATE_MIP;
    case D3DSAMP_MIPMAPLODBIAS: return SAMPLER_STATE_LOD_BIAS;
    default: return -1;
    }
}

static void SetDefaultsLocked() {
    g_config.smoothTextures = false;
    g_config.smoothTextureBias = kDefaultSmoothTextureBias;
    g_config.worldFogEnabled = false;
    g_config.worldFogColor = D3DCOLOR_ARGB(255, 170, 170, 170);
    g_config.worldFogStart = 500.0f;
    g_config.worldFogEnd = 2500.0f;
    g_config.worldFarClipEnabled = false;
    g_config.worldFarClip = 2666.0f;
}

static void SetConfigBool(bool* target, bool enabled) {
    if (!g_lockReady || !target) {
        return;
    }

    EnterCriticalSection(&g_lock);
    *target = enabled;
    LeaveCriticalSection(&g_lock);
}

static void CaptureNativeFogState(D3DRENDERSTATETYPE state, DWORD value) {
    switch (state) {
    case D3DRS_FOGENABLE:
        g_nativeFogState.hasEnable = true;
        g_nativeFogState.enable = value;
        break;
    case D3DRS_FOGCOLOR:
        g_nativeFogState.hasColor = true;
        g_nativeFogState.color = value;
        break;
    case D3DRS_FOGSTART:
        g_nativeFogState.hasStart = true;
        g_nativeFogState.start = value;
        break;
    case D3DRS_FOGEND:
        g_nativeFogState.hasEnd = true;
        g_nativeFogState.end = value;
        break;
    case D3DRS_FOGTABLEMODE:
        g_nativeFogState.hasTableMode = true;
        g_nativeFogState.tableMode = value;
        break;
    case D3DRS_FOGVERTEXMODE:
        g_nativeFogState.hasVertexMode = true;
        g_nativeFogState.vertexMode = value;
        break;
    case D3DRS_RANGEFOGENABLE:
        g_nativeFogState.hasRange = true;
        g_nativeFogState.range = value;
        break;
    default:
        break;
    }
}

static void RestoreNativeFogState(IDirect3DDevice9* device) {
    if (!device) {
        return;
    }

    if (g_nativeFogState.hasEnable) device->SetRenderState(D3DRS_FOGENABLE, g_nativeFogState.enable);
    if (g_nativeFogState.hasColor) device->SetRenderState(D3DRS_FOGCOLOR, g_nativeFogState.color);
    if (g_nativeFogState.hasStart) device->SetRenderState(D3DRS_FOGSTART, g_nativeFogState.start);
    if (g_nativeFogState.hasEnd) device->SetRenderState(D3DRS_FOGEND, g_nativeFogState.end);
    if (g_nativeFogState.hasTableMode) device->SetRenderState(D3DRS_FOGTABLEMODE, g_nativeFogState.tableMode);
    if (g_nativeFogState.hasVertexMode) device->SetRenderState(D3DRS_FOGVERTEXMODE, g_nativeFogState.vertexMode);
    if (g_nativeFogState.hasRange) device->SetRenderState(D3DRS_RANGEFOGENABLE, g_nativeFogState.range);
}

static void CaptureNativeSamplerState(DWORD sampler, D3DSAMPLERSTATETYPE type, DWORD value) {
    if (sampler >= 16) {
        return;
    }

    const int index = GetTrackedSamplerStateIndex(type);
    if (index < 0) {
        return;
    }

    g_nativeSamplerState.valid[sampler][index] = true;
    g_nativeSamplerState.value[sampler][index] = value;
}

static void RestoreNativeSamplerState(IDirect3DDevice9* device) {
    if (!device) {
        return;
    }

    for (DWORD sampler = 0; sampler < 16; ++sampler) {
        if (g_nativeSamplerState.valid[sampler][SAMPLER_STATE_MIN]) {
            device->SetSamplerState(sampler, D3DSAMP_MINFILTER, g_nativeSamplerState.value[sampler][SAMPLER_STATE_MIN]);
        }
        if (g_nativeSamplerState.valid[sampler][SAMPLER_STATE_MAG]) {
            device->SetSamplerState(sampler, D3DSAMP_MAGFILTER, g_nativeSamplerState.value[sampler][SAMPLER_STATE_MAG]);
        }
        if (g_nativeSamplerState.valid[sampler][SAMPLER_STATE_MIP]) {
            device->SetSamplerState(sampler, D3DSAMP_MIPFILTER, g_nativeSamplerState.value[sampler][SAMPLER_STATE_MIP]);
        }
        if (g_nativeSamplerState.valid[sampler][SAMPLER_STATE_LOD_BIAS]) {
            device->SetSamplerState(sampler, D3DSAMP_MIPMAPLODBIAS, g_nativeSamplerState.value[sampler][SAMPLER_STATE_LOD_BIAS]);
        } else {
            device->SetSamplerState(sampler, D3DSAMP_MIPMAPLODBIAS, FloatToDword(0.0f));
        }
    }
}

static void SyncWorldState() {
    if (!g_lockReady || g_isProcessTerminating) {
        return;
    }

    RenderOverrideConfig cfg = {};
    EnterCriticalSection(&g_lock);
    cfg = g_config;
    LeaveCriticalSection(&g_lock);

    __try {
        if (!g_worldOriginalFarClipCaptured) {
            g_worldOriginalFarClip = GetSafeFarClip(*(float*)ADDR_WORLD_FARCLIP);
            g_worldOriginalFarClipCaptured = true;
        }

        const float farClip = cfg.worldFarClipEnabled
            ? ClampFarClip(cfg.worldFarClip)
            : GetSafeFarClip(g_worldOriginalFarClip);

        DWORD oldProtect = 0;
        if (VirtualProtect((void*)ADDR_WORLD_FARCLIP, sizeof(float), PAGE_EXECUTE_READWRITE, &oldProtect)) {
            *(float*)ADDR_WORLD_FARCLIP = farClip;
            VirtualProtect((void*)ADDR_WORLD_FARCLIP, sizeof(float), oldProtect, &oldProtect);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
}

static void ApplyFogState(IDirect3DDevice9* device, const RenderOverrideConfig& cfg) {
    if (!device) {
        return;
    }

    if (!cfg.worldFogEnabled) {
        RestoreNativeFogState(device);
        return;
    }

    device->SetRenderState(D3DRS_FOGENABLE, TRUE);
    device->SetRenderState(D3DRS_FOGTABLEMODE, D3DFOG_LINEAR);
    device->SetRenderState(D3DRS_FOGVERTEXMODE, D3DFOG_LINEAR);
    device->SetRenderState(D3DRS_RANGEFOGENABLE, FALSE);
    device->SetRenderState(D3DRS_FOGCOLOR, cfg.worldFogColor & 0x00FFFFFF);
    device->SetRenderState(D3DRS_FOGSTART, FloatToDword(cfg.worldFogStart));
    device->SetRenderState(D3DRS_FOGEND, FloatToDword(cfg.worldFogEnd));
}

static void ApplySmoothTextureState(IDirect3DDevice9* device, const RenderOverrideConfig& cfg) {
    if (!device) {
        return;
    }

    if (!cfg.smoothTextures) {
        RestoreNativeSamplerState(device);
        return;
    }

    const DWORD smoothBias = FloatToDword(cfg.smoothTextureBias);
    for (DWORD sampler = 0; sampler < 16; ++sampler) {
        device->SetSamplerState(sampler, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
        device->SetSamplerState(sampler, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);
        device->SetSamplerState(sampler, D3DSAMP_MIPFILTER, D3DTEXF_LINEAR);
        device->SetSamplerState(sampler, D3DSAMP_MIPMAPLODBIAS, smoothBias);
    }
}

} // namespace

void RenderOverrides_Initialize() {
    if (g_lockReady) {
        return;
    }

    InitializeCriticalSection(&g_lock);
    g_lockReady = true;

    EnterCriticalSection(&g_lock);
    SetDefaultsLocked();
    LeaveCriticalSection(&g_lock);

    SyncWorldState();
}

void RenderOverrides_Shutdown() {
    if (!g_lockReady) {
        return;
    }

    if (!g_isProcessTerminating) {
        EnterCriticalSection(&g_lock);
        g_config.worldFarClipEnabled = false;
        LeaveCriticalSection(&g_lock);
        SyncWorldState();
    }

    DeleteCriticalSection(&g_lock);
    g_lockReady = false;
}

void RenderOverrides_SetSmoothTextures(bool enabled) { SetConfigBool(&g_config.smoothTextures, enabled); }

void RenderOverrides_SetSmoothTextureBias(float value) {
    if (!g_lockReady) {
        return;
    }

    value = ClampSmoothTextureBias(value);
    EnterCriticalSection(&g_lock);
    g_config.smoothTextureBias = value;
    LeaveCriticalSection(&g_lock);
}

void RenderOverrides_SetWorldFogEnabled(bool enabled) {
    EnterCriticalSection(&g_lock);
    g_config.worldFogEnabled = enabled;
    LeaveCriticalSection(&g_lock);
}

void RenderOverrides_SetWorldFogColor(D3DCOLOR color) {
    EnterCriticalSection(&g_lock);
    g_config.worldFogColor = color | 0xFF000000;
    LeaveCriticalSection(&g_lock);
}

void RenderOverrides_SetWorldFogStart(float value) {
    EnterCriticalSection(&g_lock);
    g_config.worldFogStart = ClampFogStartValue(value);
    if (g_config.worldFogEnd <= g_config.worldFogStart + 1.0f) {
        g_config.worldFogEnd = g_config.worldFogStart + 1.0f;
    }
    LeaveCriticalSection(&g_lock);
}

void RenderOverrides_SetWorldFogEnd(float value) {
    EnterCriticalSection(&g_lock);
    g_config.worldFogEnd = ClampFogEndValue(value);
    if (g_config.worldFogStart >= g_config.worldFogEnd - 1.0f) {
        g_config.worldFogStart = g_config.worldFogEnd - 1.0f;
    }
    LeaveCriticalSection(&g_lock);
}

void RenderOverrides_SetWorldFarClipEnabled(bool enabled) {
    EnterCriticalSection(&g_lock);
    g_config.worldFarClipEnabled = enabled;
    LeaveCriticalSection(&g_lock);
    SyncWorldState();
}

void RenderOverrides_SetWorldFarClip(float distance) {
    EnterCriticalSection(&g_lock);
    g_config.worldFarClip = ClampFarClip(distance);
    LeaveCriticalSection(&g_lock);
    SyncWorldState();
}

void RenderOverrides_RefreshWorldState() {
    SyncWorldState();
}

bool RenderOverrides_OnSetRenderState(IDirect3DDevice9* device, D3DRENDERSTATETYPE state, DWORD* value) {
    (void)device;
    if (!value || !g_lockReady) {
        return false;
    }

    RenderOverrideConfig cfg = {};
    EnterCriticalSection(&g_lock);
    cfg = g_config;
    LeaveCriticalSection(&g_lock);

    if (!cfg.worldFogEnabled) {
        CaptureNativeFogState(state, *value);
        return false;
    }

    if (state == D3DRS_FOGENABLE) {
        *value = TRUE;
    } else if (state == D3DRS_FOGTABLEMODE || state == D3DRS_FOGVERTEXMODE) {
        *value = D3DFOG_LINEAR;
    } else if (state == D3DRS_RANGEFOGENABLE) {
        *value = FALSE;
    } else if (state == D3DRS_FOGCOLOR) {
        *value = cfg.worldFogColor & 0x00FFFFFF;
    } else if (state == D3DRS_FOGSTART) {
        *value = FloatToDword(cfg.worldFogStart);
    } else if (state == D3DRS_FOGEND) {
        *value = FloatToDword(cfg.worldFogEnd);
    }

    return false;
}

bool RenderOverrides_OnSetSamplerState(IDirect3DDevice9* device, DWORD sampler, D3DSAMPLERSTATETYPE type, DWORD* value) {
    (void)device;
    if (!value || !g_lockReady) {
        return false;
    }

    CaptureNativeSamplerState(sampler, type, *value);

    RenderOverrideConfig cfg = {};
    EnterCriticalSection(&g_lock);
    cfg = g_config;
    LeaveCriticalSection(&g_lock);

    if (!cfg.smoothTextures) {
        return false;
    }

    if (type == D3DSAMP_MAGFILTER || type == D3DSAMP_MINFILTER || type == D3DSAMP_MIPFILTER) {
        *value = D3DTEXF_LINEAR;
    } else if (type == D3DSAMP_MIPMAPLODBIAS) {
        *value = FloatToDword(cfg.smoothTextureBias);
    }

    return false;
}

void RenderOverrides_ApplyDeviceOverrides(IDirect3DDevice9* device) {
    if (!device || !g_lockReady) {
        return;
    }

    RenderOverrideConfig cfg = {};
    EnterCriticalSection(&g_lock);
    cfg = g_config;
    LeaveCriticalSection(&g_lock);

    ApplyFogState(device, cfg);
    ApplySmoothTextureState(device, cfg);
}
