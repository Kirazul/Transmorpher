#include "RenderEnables.h"

#include <windows.h>

#include "Utils.h"

namespace {

static const DWORD kRenderEnablesAddress = 0x00CD774C;

struct RenderFlagDef {
    const char* name;
    DWORD mask;
    bool defaultEnabled;
};

enum RenderFlagIndex {
    kRenderFlagM2 = 0,
    kRenderFlagTerrain,
    kRenderFlagTerrainCulling,
    kRenderFlagM2WmoShadow,
    kRenderFlagWmo,
    kRenderFlagWmoLighting,
    kRenderFlagFootprints,
    kRenderFlagWmoTextures,
    kRenderFlagWmoPortals,
    kRenderFlagOccluders,
    kRenderFlagM2Fade,
    kRenderFlagGroundClutter,
    kRenderFlagCollision,
    kRenderFlagLiquidSurface,
    kRenderFlagLiquidParticles,
    kRenderFlagMountains,
    kRenderFlagSpecularLighting,
    kRenderFlagRenderObjectShadow,
    kRenderFlagWireframe,
    kRenderFlagNormals,
    kRenderFlagCount
};

static const RenderFlagDef kRenderFlags[kRenderFlagCount] = {
    { "m2",                 0x00000001, true  },
    { "terrain",            0x00000002, true  },
    { "terrainCulling",     0x00000020, true  },
    { "m2WmoShadow",        0x00000040, true  },
    { "wmo",                0x00000100, true  },
    { "wmoLighting",        0x00000200, true  },
    { "footprints",         0x00000400, true  },
    { "wmoTextures",        0x00000800, true  },
    { "wmoPortals",         0x00001000, false },
    { "occluders",          0x00002000, false },
    { "m2Fade",             0x00004000, true  },
    { "groundClutter",      0x00100000, true  },
    { "collision",          0x00200000, false },
    { "liquidSurface",      0x01000000, true  },
    { "liquidParticles",    0x02000000, true  },
    { "mountains",          0x04000000, true  },
    { "specularLighting",   0x08000000, true  },
    { "renderObjectShadow", 0x10000000, true  },
    { "wireframe",          0x20000000, false },
    { "normals",            0x40000000, false },
};

struct RenderEnableConfig {
    bool enabled[kRenderFlagCount];
};

static CRITICAL_SECTION g_lock;
static bool g_lockReady = false;
static RenderEnableConfig g_config = {};
static DWORD g_originalFlags = 0;
static bool g_originalFlagsCaptured = false;
static DWORD g_lastAppliedFlags = 0;
static bool g_lastAppliedValid = false;

static DWORD GetKnownRenderMask() {
    DWORD mask = 0;
    for (int i = 0; i < kRenderFlagCount; ++i) {
        mask |= kRenderFlags[i].mask;
    }
    return mask;
}

static bool ReadFlags(DWORD* value) {
    if (!value) return false;
    __try {
        *value = *(DWORD*)(uintptr_t)kRenderEnablesAddress;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

static bool WriteFlags(DWORD value) {
    __try {
        *(DWORD*)(uintptr_t)kRenderEnablesAddress = value;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

static void SetFlagSetting(RenderFlagIndex index, bool enabled) {
    if (!g_lockReady) return;
    EnterCriticalSection(&g_lock);
    g_config.enabled[index] = enabled;
    LeaveCriticalSection(&g_lock);
}

} // namespace

void RenderEnables_Initialize() {
    if (g_lockReady) return;
    InitializeCriticalSection(&g_lock);
    g_lockReady = true;

    for (int i = 0; i < kRenderFlagCount; ++i) {
        g_config.enabled[i] = kRenderFlags[i].defaultEnabled;
    }

    DWORD flags = 0;
    if (ReadFlags(&flags)) {
        g_originalFlags = flags;
        g_originalFlagsCaptured = true;
        g_lastAppliedFlags = flags;
        g_lastAppliedValid = true;

        EnterCriticalSection(&g_lock);
        for (int i = 0; i < kRenderFlagCount; ++i) {
            g_config.enabled[i] = (flags & kRenderFlags[i].mask) != 0;
        }
        LeaveCriticalSection(&g_lock);
    }
}

void RenderEnables_Shutdown() {
    if (!g_lockReady) return;
    if (g_originalFlagsCaptured) {
        WriteFlags(g_originalFlags);
    }
    DeleteCriticalSection(&g_lock);
    g_lockReady = false;
}

void RenderEnables_Apply() {
    if (!g_lockReady) return;

    DWORD currentFlags = 0;
    if (!ReadFlags(&currentFlags)) return;

    if (!g_originalFlagsCaptured) {
        g_originalFlags = currentFlags;
        g_originalFlagsCaptured = true;
    }

    RenderEnableConfig cfg = {};
    EnterCriticalSection(&g_lock);
    cfg = g_config;
    LeaveCriticalSection(&g_lock);

    DWORD flags = 0;
    for (int i = 0; i < kRenderFlagCount; ++i) {
        if (cfg.enabled[i]) {
            flags |= kRenderFlags[i].mask;
        }
    }

    const DWORD knownMask = GetKnownRenderMask();
    flags = (currentFlags & ~knownMask) | (flags & knownMask);

    if (WriteFlags(flags)) {
        g_lastAppliedFlags = flags;
        g_lastAppliedValid = true;
    }
}

void RenderEnables_SetM2(bool enabled) { SetFlagSetting(kRenderFlagM2, enabled); }
void RenderEnables_SetTerrain(bool enabled) { SetFlagSetting(kRenderFlagTerrain, enabled); }
void RenderEnables_SetTerrainCulling(bool enabled) { SetFlagSetting(kRenderFlagTerrainCulling, enabled); }
void RenderEnables_SetM2WmoShadow(bool enabled) { SetFlagSetting(kRenderFlagM2WmoShadow, enabled); }
void RenderEnables_SetWmo(bool enabled) { SetFlagSetting(kRenderFlagWmo, enabled); }
void RenderEnables_SetWmoLighting(bool enabled) { SetFlagSetting(kRenderFlagWmoLighting, enabled); }
void RenderEnables_SetFootprints(bool enabled) { SetFlagSetting(kRenderFlagFootprints, enabled); }
void RenderEnables_SetWmoTextures(bool enabled) { SetFlagSetting(kRenderFlagWmoTextures, enabled); }
void RenderEnables_SetWmoPortals(bool enabled) { SetFlagSetting(kRenderFlagWmoPortals, enabled); }
void RenderEnables_SetOccluders(bool enabled) { SetFlagSetting(kRenderFlagOccluders, enabled); }
void RenderEnables_SetM2Fade(bool enabled) { SetFlagSetting(kRenderFlagM2Fade, enabled); }
void RenderEnables_SetGroundClutter(bool enabled) { SetFlagSetting(kRenderFlagGroundClutter, enabled); }
void RenderEnables_SetCollision(bool enabled) { SetFlagSetting(kRenderFlagCollision, enabled); }
void RenderEnables_SetLiquidSurface(bool enabled) { SetFlagSetting(kRenderFlagLiquidSurface, enabled); }
void RenderEnables_SetLiquidParticles(bool enabled) { SetFlagSetting(kRenderFlagLiquidParticles, enabled); }
void RenderEnables_SetMountains(bool enabled) { SetFlagSetting(kRenderFlagMountains, enabled); }
void RenderEnables_SetSpecularLighting(bool enabled) { SetFlagSetting(kRenderFlagSpecularLighting, enabled); }
void RenderEnables_SetRenderObjectShadow(bool enabled) { SetFlagSetting(kRenderFlagRenderObjectShadow, enabled); }
void RenderEnables_SetWireframe(bool enabled) { SetFlagSetting(kRenderFlagWireframe, enabled); }
void RenderEnables_SetNormals(bool enabled) { SetFlagSetting(kRenderFlagNormals, enabled); }
