#include "Morpher.h"
#include "WoWOffsets.h"
#include "Utils.h"
#include "Hooks.h"
#include "Logger.h"
#include "SpellMorph.h"
#include "SpellClass.h"
#include "ColorEngine.h"
#include "UnitHider.h"
#include "PlayerSoundFilter.h"
#include "Visuals.h"
#include "MSDF.h"
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <unordered_map>
#include <cstdint>

// ================================================================
// State Variables
// ================================================================
DWORD g_playerDescBase = 0;
bool g_suspended = false;

// Originals
uint32_t g_origDisplay = 0;
uint32_t g_origItems[20] = {0};
float g_origScale = 1.0f;
static bool g_saved = false;
uint32_t g_origMount = 0;
static uint32_t g_origPetDisplay = 0;
static uint32_t g_origHPetDisplay = 0;
uint32_t g_origEnchantMH = 0;
uint32_t g_origEnchantOH = 0;
uint32_t g_origTitle = 0;
// Original player appearance (skin/face/hair) so a player-clone Copy-Target can
// be reverted exactly. Captured on first morph, restored on reset.
uint32_t g_origPlayerBytes = 0;     // PLAYER_FIELD_BYTES dword (skin/face/hair)
uint8_t  g_origPlayerFacial = 0;    // PLAYER_FIELD_BYTES2 byte0 (facial hair)
bool     g_origPlayerBytesSaved = false;
// When set, MorphGuard keeps re-stamping this appearance each tick (the engine
// rebuilds the player byte fields on refresh, which would revert our clone).
uint32_t g_morphPlayerBytes = 0;
uint8_t  g_morphPlayerFacial = 0;
bool     g_morphPlayerBytesActive = false;

// ---- Barber: the user re-styling THEIR OWN base model ------------------------
// Independent of the player-clone bytes above. These are written into the local
// player's PLAYER_BYTES (b0 skin / b1 face / b2 hairStyle / b3 hairColor) and
// PLAYER_BYTES_2 (b0 facialHair) descriptor fields. The engine re-derives these
// fields on every model rebuild/zone, so MorphGuard re-stamps them while active.
// Verified layout (3.3.5a 12340): PLAYER_BYTES = field 0x99 (byte 0x264),
// PLAYER_BYTES_2 = field 0x9A (byte 0x268); same fields the working player-clone
// path copies. Persisted in the state file reserved[2]/[3] (no version bump).
bool     g_barberActive    = false;
uint8_t  g_barberSkin      = 0;
uint8_t  g_barberFace      = 0;
uint8_t  g_barberHair      = 0;
uint8_t  g_barberHairColor = 0;
uint8_t  g_barberFacial    = 0;
// The character's TRUE (server) appearance, captured the first time barber stamps
// so "Reset barber" restores the real look exactly. Re-captured fresh each login.
uint32_t g_barberOrigBytes  = 0;
uint8_t  g_barberOrigFacial = 0;
bool     g_barberOrigSaved  = false;

// Live mirror of the four free-RGB barber recolor regions (0 skin, 1 face, 2 hair,
// 3 facial). Updated whenever a BARBER_TINT/OFF/CLEAR command arrives and flushed to a
// per-guid sidecar file, so the COLORS persist and can be replayed onto the cold-start
// character-select doll (the addon isn't running at the glue screen, so it can't push
// them itself — that was why colors only appeared after a world round-trip).
SlotSkinTint g_barberTint[4] = {};

static inline uint32_t BarberPackBytes() {
    return (uint32_t)g_barberSkin
         | ((uint32_t)g_barberFace      << 8)
         | ((uint32_t)g_barberHair      << 16)
         | ((uint32_t)g_barberHairColor << 24);
}

// Active Morphs
uint32_t g_morphDisplay = 0; // Made global for Hooks.cpp
uint32_t g_morphItems[20] = {0}; // Made global
// Per-slot source item id that a slot-based skin (ITEM_RETEX_SLOT) was applied to,
// so we can remove exactly that retex later even if the worn item changes.
uint32_t g_slotRetexFrom[20] = {0};
uint32_t g_slotTintFrom[20] = {0};
uint32_t g_slotRetexTo[20] = {0};
SlotSkinTint g_slotTintApplied[20] = {};

// Persistent per-slot skin (the "donor" item id the slot is currently retextured
// to) and tint parameters. Pushed from Lua via ITEM_SKIN_PERSIST whenever the user
// commits a skin, and flushed to the per-character state file so the
// character-select doll renders the same look. Re-applied on world entry by
// SkinTab.Skin_ApplyAll (Lua) once the descriptor fields are available.
uint32_t g_skinToItem[20] = {0};   // 0 = no skin; else item id of donor
SlotSkinTint g_skinTint[20] = {};   // mirror of the Lua tint struct (zeros = no tint)
uint32_t g_skinAppliedTo[20] = {0}; // visible item id this slot skin is allowed to bind to
float g_morphScale = 0.0f; // Made global
uint32_t g_morphMount = 0;
static uint32_t g_morphPet = 0;
static uint32_t g_morphHPet = 0;
static float g_morphHPetScale = 0.0f;
uint32_t g_morphEnchantMH = 0; // Made global
uint32_t g_morphEnchantOH = 0; // Made global
uint32_t g_morphTitle = 0;
uint32_t g_luaMounted = 0;
bool g_forceCharacterStateReload = false;

// Behavior Settings
uint32_t g_showDBW = 1;
uint32_t g_showMeta = 1;
uint32_t g_keepShapeshift = 0;

// Maximum number of spell-morph pairs persisted to the state file. Defined
// here (not at the top of the file) so the v4 / v5 packed structs below can
// use it in their array bounds.
static const uint32_t MAX_PERSISTED_SPELL_MORPHS = 128;

// v4 SlotSkinTint layout: 38-byte entries, no post-effect fields. The current
// (v5) layout is 50 bytes (added brightness/saturation/hueShift). Used only on
// the read path to upgrade a legacy v4 save to the v5 in-memory representation
// in one shot — the legacy struct exists so the file can be fread in full and
// the per-slot tint can be memcpy-extended into the live (v5) array.
#pragma pack(push, 1)
struct SlotSkinTintV4 {
    uint32_t enabled;
    uint32_t mode;
    uint8_t  r, g, b;
    uint8_t  r2, g2, b2;
    uint32_t dir;
    uint32_t mult;
    uint32_t glowStr;
    uint32_t contrast;
    uint32_t span;
    uint32_t phase;
};
struct PersistentMorphStateV4 {
    uint32_t magic;
    uint32_t version;
    uint32_t morphDisplay;
    float morphScale;
    uint32_t morphMount;
    uint32_t morphEnchantMH;
    uint32_t morphEnchantOH;
    uint32_t morphTitle;
    uint32_t morphItems[20];
    uint32_t spellMorphCount;
    SpellMorphPair spellMorphs[MAX_PERSISTED_SPELL_MORPHS];
    uint32_t skinToItem[20];
    SlotSkinTintV4 skinTint[20];
    uint32_t reserved[4];
};
#pragma pack(pop)
static_assert(sizeof(SlotSkinTintV4) == 38, "SlotSkinTintV4 size drifted");

// Copy a v4 slot tint (38 bytes) into a v5 slot tint (50 bytes). The new
// post-effect fields (brightness/saturation/hueShift) are filled with neutral
// defaults so the on-screen result is unchanged when a legacy save is loaded:
// brightness=128 (no scaling), saturation=0 (no shift), hueShift=0 (no shift).
static inline void UpgradeV4TintToV5(const SlotSkinTintV4* src, SlotSkinTint* dst) {
    dst->enabled  = src->enabled;
    dst->mode     = src->mode;
    dst->r        = src->r;
    dst->g        = src->g;
    dst->b        = src->b;
    dst->r2       = src->r2;
    dst->g2       = src->g2;
    dst->b2       = src->b2;
    dst->dir      = src->dir;
    dst->mult     = src->mult;
    dst->glowStr  = src->glowStr;
    dst->contrast = src->contrast;
    dst->span     = src->span;
    dst->phase    = src->phase;
    dst->brightness = 128;
    dst->saturation = 0;
    dst->hueShift   = 0;
}

// Multiplayer Sync Data
std::unordered_map<uint64_t, RemoteMorph> g_remoteMorphs;

// Debug
uint32_t g_debugLastDisplayID = 0;

// Anti-Flicker Engine
int g_updateCooldown = 0;             // Ticks to suppress UpdateDisplayInfo
uint32_t g_lastAppliedDisplay = 0;    // Last display ID we wrote
uint32_t g_lastAppliedMount = 0;      // Last mount ID we wrote

static const uint32_t HIDDEN_SENTINEL = UINT32_MAX;
static bool g_hasMorph = false;
// True when ANY slot carries a persisted skin (donor retex and/or tint). Drives the
// same login/enforcement paths as g_hasMorph so a skin-only character still gets its
// look applied before the first rendered frame (no flicker) and re-bound on rebuilds.
static bool g_hasSkin = false;
static int g_weaponRefreshTicks = 0;
// Set by ApplyPersistedSkins when at least one slot's visible item id changed in this
// pass — i.e. a gear/weapon swap in the inventory rather than a slider change on an
// unchanged item. Read by MorphGuard to pick the right refresh path: a gear-swap pass
// re-uses the engine's own component re-attach (the M2 was already re-streamed by the
// engine as part of the descriptor change), so we only need to nudge the BLPs through
// the decode hook with the new tint. A plain RefreshPlayerModelFull on a swap does 4
// cascading M2 disposals and tears the model down for a frame → "invisible for a sec".
static bool s_skinPassWasGearSwap = false;

static void ReapplyActiveBarberTintsForPlayer(WowObject* player);

void UpdateHasMorph() {
    g_hasMorph = false;
    if (g_morphDisplay > 0) { g_hasMorph = true; return; }
    if (g_morphScale > 0.0f) { g_hasMorph = true; return; }
    if (g_morphMount > 0)   { g_hasMorph = true; return; }
    if (g_morphPet > 0)     { g_hasMorph = true; return; }
    if (g_morphHPet > 0)    { g_hasMorph = true; return; }
    if (g_morphEnchantMH > 0) { g_hasMorph = true; return; }
    if (g_morphEnchantOH > 0) { g_hasMorph = true; return; }
    if (g_morphTitle > 0)   { g_hasMorph = true; return; }
    for (int s = 1; s <= 19; s++) {
        if (g_morphItems[s] > 0) { g_hasMorph = true; return; }
    }
}

// Recompute g_hasSkin from the persisted skin tables (call after the skin state
// changes: state load, ITEM_SKIN_PERSIST, ITEM_RETEX_CLEAR).
void UpdateHasSkin() {
    g_hasSkin = false;
    for (int s = 1; s <= 19; s++) {
        if (g_skinToItem[s] > 0 || g_skinTint[s].enabled) { g_hasSkin = true; return; }
    }
}

// ================================================================
// FULL STATE PERSISTENCE
// Saves ALL morph targets to disk atomically so morphs survive
// full client restarts without needing /reload or Lua restoration.
// ================================================================
static const uint32_t STATE_FILE_MAGIC = 0x544D5246; // 'TMRF'
static const uint32_t STATE_FILE_VERSION = 6;

static char g_dllDir[MAX_PATH] = {0};
static bool g_initialRefreshDone = false;
static uint64_t g_lastLoadedGuid = 0;

// Deferred initial refresh is intentionally disabled. The descriptor state is
// already enforced immediately on world entry; firing a second component/model
// refresh about 1s later was the visible login/reload/teleport blink.
static const int INITIAL_REFRESH_DELAY_TICKS = 0;
static int g_pendingInitialRefreshTicks = 0;

// Coalesced skin/recolor rebuild. The Skin tab fans out one descriptor command per
// slot (e.g. "Color All" / "Clear Color All" send up to 19 ITEM_TINTX/DEL commands
// in a single frame). Doing a full body re-bake inside EACH command both flickers
// and races the compositor's async texture release — which is exactly why a removal
// "sometimes" needed a relog. Instead every recolor command just arms this counter;
// the tick loop fires one component re-attach after the batch settles. Next tick keeps
// same-frame texture work out of the engine's active decode path without a
// noticeable delayed rebuild.
static const int SKIN_REFRESH_DELAY_TICKS = 1;
int g_pendingSkinRefreshTicks = 0;
// Set when the pending refresh must force object-component attachments (helmet/
// shoulder/cape/weapon) to re-resolve their CTexture instead of keeping an old one.
// Resets need it to drop stale color; applies need it for models that keep their
// pre-existing texture object even after a fresh virtual tint key is registered.
bool g_pendingSkinHardReload = false;
// Separate-model items (helm/shoulder/cape/weapon) can keep an already-loaded
// CTexture* while the new tint redirect is active. Reload those exact texture
// objects after the command batch settles so live apply matches cold-start load.
static uint32_t g_pendingModelTintReload[20] = {0};

// ---------------------------------------------------------------------------
// Camera FOV (client-side field-of-view control)
// Verified against wow.exe: GetActiveCamera @ 0x004F5960 returns a CSimpleCamera*
// whose float m_fov (radians) lives at +0x40 (see font_exact/GameClient.h). We
// set it live each tick instead of hooking the constructor — no Detour, no CVar.
// g_cameraFovDeg == 0 means "leave the client default untouched".
// ---------------------------------------------------------------------------
static float g_cameraFovDeg = 0.0f; // 0 = off; otherwise 20..350 degrees
static float g_originalCameraFovRad = 0.0f; // captured from client before first override
static bool g_originalCameraFovCaptured = false;
typedef void* (__cdecl* GetActiveCamera_fn)();

void ApplyCameraFov() {
    GetActiveCamera_fn getCam = reinterpret_cast<GetActiveCamera_fn>(0x004F5960);
    void* cam = nullptr;
    __try { cam = getCam(); } __except (EXCEPTION_EXECUTE_HANDLER) { return; }
    if (!cam || reinterpret_cast<uintptr_t>(cam) < 0x10000) return;

    if (g_cameraFovDeg <= 0.0f) {
        // Restore the original client FOV that was captured before the first override.
        if (g_originalCameraFovCaptured) {
            __try { *reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(cam) + 0x40) = g_originalCameraFovRad; }
            __except (EXCEPTION_EXECUTE_HANDLER) {}
        }
        return;
    }

    // Capture the original FOV once before applying the first override.
    if (!g_originalCameraFovCaptured) {
        __try { g_originalCameraFovRad = *reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(cam) + 0x40); }
        __except (EXCEPTION_EXECUTE_HANDLER) { g_originalCameraFovRad = 1.3962634f; } // ~80 degrees fallback
        g_originalCameraFovCaptured = true;
    }

    const float fovRad = g_cameraFovDeg * (3.14159265f / 180.0f);
    __try { *reinterpret_cast<float*>(reinterpret_cast<uint8_t*>(cam) + 0x40) = fovRad; }
    __except (EXCEPTION_EXECUTE_HANDLER) {}
}

void SetCameraFov(float degrees) {
    if (degrees <= 0.0f) {
        g_cameraFovDeg = 0.0f;
        ApplyCameraFov();  // restore original FOV
        return;
    }
    if (degrees < 20.0f) degrees = 20.0f;
    if (degrees > 350.0f) degrees = 350.0f;  // allow very wide (fish-eye) FOV
    g_cameraFovDeg = degrees;
    ApplyCameraFov();
}

// ---------------------------------------------------------------------------
// Weapon sheath position override (per slot). See Morpher.h for the RE notes.
// -1 = natural (let the item's own sheathe type decide). Otherwise the value is
// returned from GetSheatheType for the LOCAL player's matching weapon.
// ---------------------------------------------------------------------------
static volatile LONG g_sheatheMH = -1;   // main-hand override (-1 = off)
static volatile LONG g_sheatheOH = -1;   // off-hand override  (-1 = off)
void* g_oGetSheatheType = reinterpret_cast<void*>(0x00758F50);

// Hook: for the local player's main/off-hand item id, force the chosen sheathe
// type; everything else (other units, other slots) passes through untouched.
int __fastcall Morpher_hkGetSheatheType(void* This, void* edx) {
    typedef int(__fastcall* fn)(void*, void*);
    int orig = reinterpret_cast<fn>(g_oGetSheatheType)(This, edx);
    if (g_sheatheMH < 0 && g_sheatheOH < 0) return orig;   // fast path: no override
    uint32_t itemId = 0;
    __try { itemId = *reinterpret_cast<uint32_t*>(This); }
    __except (EXCEPTION_EXECUTE_HANDLER) { return orig; }
    int ov = SheatheOverrideForItem(itemId);
    return (ov >= 0) ? ov : orig;
}

// Returns the override value if itemId is the local player's current main- or
// off-hand visible item, else -1. Reads the descriptor so it follows morphs (the
// morph rewrites the VISIBLE_ITEM entry, so the displayed weapon's id matches).
int SheatheOverrideForItem(uint32_t itemId) {
    if (itemId == 0) return -1;
    if (g_sheatheMH < 0 && g_sheatheOH < 0) return -1;
    WowObject* p = GetPlayer();
    if (!p || !p->descriptors) return -1;
    uint32_t mh = 0, oh = 0;
    __try {
        uint8_t* d = reinterpret_cast<uint8_t*>(p->descriptors);
        mh = *reinterpret_cast<uint32_t*>(d + GetVisibleItemField(16)); // logical 16 = MainHand
        oh = *reinterpret_cast<uint32_t*>(d + GetVisibleItemField(17)); // logical 17 = OffHand
    } __except (EXCEPTION_EXECUTE_HANDLER) { return -1; }
    if (g_sheatheMH >= 0 && itemId == mh) return (int)g_sheatheMH;
    if (g_sheatheOH >= 0 && itemId == oh) return (int)g_sheatheOH;
    return -1;
}

void SetSheatheOverride(int slot, int value) {
    if (slot == 0)      InterlockedExchange(&g_sheatheMH, value);
    else if (slot == 1) InterlockedExchange(&g_sheatheOH, value);
    Log("[Sheathe] slot=%d value=%d (MH=%d OH=%d)", slot, value, (int)g_sheatheMH, (int)g_sheatheOH);
}

static uint64_t UnitGuid(WowObject* unit) {
    if (!unit || !unit->descriptors) return 0;
    __try { return *reinterpret_cast<uint64_t*>(unit->descriptors); }
    __except (EXCEPTION_EXECUTE_HANDLER) { return 0; }
}

static void ScopedUpdateDisplayInfo(WowObject* player, int flags) {
    if (!player || !CGUnit_UpdateDisplayInfo) return;
    __try { CGUnit_UpdateDisplayInfo(player, flags); }
    __except (EXCEPTION_EXECUTE_HANDLER) {}
}

// Re-attach the player's weapons so a sheath change is visible immediately. Uses
// the same display-id bounce as the morph refresh (re-runs the attach code that
// calls GetSheatheType), guarded by SEH.
void RefreshSheathe() {
    WowObject* player = GetPlayer();
    if (!player || !player->descriptors || !CGUnit_UpdateDisplayInfo) return;
    __try {
        uint8_t* d = reinterpret_cast<uint8_t*>(player->descriptors);
        uint32_t cur = *reinterpret_cast<uint32_t*>(d + UNIT_FIELD_DISPLAYID);
        if (cur != 0) {
            *reinterpret_cast<uint32_t*>(d + UNIT_FIELD_DISPLAYID) = 621;
            ScopedUpdateDisplayInfo(player, 0);
            *reinterpret_cast<uint32_t*>(d + UNIT_FIELD_DISPLAYID) = cur;
            ScopedUpdateDisplayInfo(player, 0);
        } else {
            ScopedUpdateDisplayInfo(player, 1);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

static void EnsureDllDir() {
    if (g_dllDir[0] == '\0') {
        GetDllDirectory(g_dllDir, sizeof(g_dllDir));
    }
}

static void EnsureStateFolders() {
    EnsureDllDir();
    char stateDir[MAX_PATH];
    sprintf_s(stateDir, sizeof(stateDir), "%s\\state", g_dllDir);
    CreateDirectoryA(stateDir, NULL);
    char charsDir[MAX_PATH];
    sprintf_s(charsDir, sizeof(charsDir), "%s\\chars", stateDir);
    CreateDirectoryA(charsDir, NULL);
}

static void GetMSDFStateFilePath(char* out, size_t size) {
    EnsureStateFolders();
    sprintf_s(out, size, "%s\\state\\msdf_mode.txt", g_dllDir);
}

static void SaveMSDFStateSetting(int mode) {
    char path[MAX_PATH];
    GetMSDFStateFilePath(path, sizeof(path));

    FILE* file = nullptr;
    if (fopen_s(&file, path, "wb") != 0 || !file) {
        Log("[MSDF] Failed to open mode file for write: %s", path);
        return;
    }

    const char value = mode != 0 ? '1' : '0';
    fwrite(&value, 1, 1, file);
    fclose(file);
    Log("[MSDF] Persisted mode %d to %s", mode != 0 ? 1 : 0, path);
}

static void GetLegacyStateFilePath(uint64_t guid, char* out, size_t size) {
    EnsureDllDir();
    if (guid == 0) {
        out[0] = '\0';
        return;
    }
    sprintf_s(out, size, "%s\\state\\transmorpher_char_%llu.dat", g_dllDir, guid);
}

static void GetStateFilePath(uint64_t guid, char* out, size_t size) {
    EnsureStateFolders();
    if (guid == 0) {
        out[0] = '\0';
        return;
    }
    char bucket[3] = {0};
    sprintf_s(bucket, sizeof(bucket), "%02X", (unsigned)(guid & 0xFF));
    char bucketDir[MAX_PATH];
    sprintf_s(bucketDir, sizeof(bucketDir), "%s\\state\\chars\\%s", g_dllDir, bucket);
    CreateDirectoryA(bucketDir, NULL);
    sprintf_s(out, size, "%s\\transmorpher_%llu.dat", bucketDir, guid);
}

static void PurgeLegacyGlobalStateFiles() {
    static bool done = false;
    if (done) return;
    done = true;
    EnsureDllDir();
    char path1[MAX_PATH];
    char path2[MAX_PATH];
    sprintf_s(path1, sizeof(path1), "%s\\state\\transmorpher_last_mount.dat", g_dllDir);
    sprintf_s(path2, sizeof(path2), "%s\\transmorpher_mount.dat", g_dllDir);
    DeleteFileA(path1);
    DeleteFileA(path2);
}

#pragma pack(push, 1)
struct PersistentMorphStateV2 {
    uint32_t magic;
    uint32_t version;
    uint32_t morphDisplay;
    float morphScale;
    uint32_t morphMount;
    uint32_t morphEnchantMH;
    uint32_t morphEnchantOH;
    uint32_t morphTitle;
    uint32_t morphItems[20];
    uint32_t reserved[8];
};

struct PersistentMorphStateV5 {
    uint32_t magic;
    uint32_t version;
    uint32_t morphDisplay;
    float morphScale;
    uint32_t morphMount;
    uint32_t morphEnchantMH;
    uint32_t morphEnchantOH;
    uint32_t morphTitle;
    uint32_t morphItems[20];
    uint32_t spellMorphCount;
    SpellMorphPair spellMorphs[MAX_PERSISTED_SPELL_MORPHS];
    uint32_t skinToItem[20];
    SlotSkinTint skinTint[20];
    uint32_t reserved[4];
};

struct PersistentMorphState {
    uint32_t magic;
    uint32_t version;
    uint32_t morphDisplay;
    float morphScale;
    uint32_t morphMount;
    uint32_t morphEnchantMH;
    uint32_t morphEnchantOH;
    uint32_t morphTitle;
    uint32_t morphItems[20];
    uint32_t spellMorphCount;
    SpellMorphPair spellMorphs[MAX_PERSISTED_SPELL_MORPHS];
    // v4+: per-slot skin (donor item id) + full tint struct. The char-select
    // doll read path uses these to apply the same retex + tint the user sees in
    // the world, so a saved skin is visible the moment a character is selected.
    uint32_t skinToItem[20];
    SlotSkinTint skinTint[20];
    // v6+: item id the slot skin/tint is anchored to. Prevents a saved color from
    // rebinding to a different item after logout/login/reload/refresh.
    uint32_t skinAppliedTo[20];
    uint32_t reserved[4];
};
#pragma pack(pop)

static void SaveToPath(const char* path) {
    PersistentMorphState state = {};
    state.magic = STATE_FILE_MAGIC;
    state.version = STATE_FILE_VERSION;
    state.morphDisplay = g_morphDisplay;
    state.morphScale = g_morphScale;
    state.morphMount = g_morphMount;
    state.morphEnchantMH = g_morphEnchantMH;
    state.morphEnchantOH = g_morphEnchantOH;
    state.morphTitle = g_morphTitle;
    memcpy(state.morphItems, g_morphItems, sizeof(g_morphItems));
    state.spellMorphCount = (uint32_t)ExportSpellMorphPairs(state.spellMorphs, MAX_PERSISTED_SPELL_MORPHS);
    memcpy(state.skinToItem, g_skinToItem, sizeof(g_skinToItem));
    memcpy(state.skinTint,   g_skinTint,   sizeof(g_skinTint));
    memcpy(state.skinAppliedTo, g_skinAppliedTo, sizeof(g_skinAppliedTo));
    // Sheath overrides ride in the v4 reserved block (+1 bias so a zero-filled
    // legacy file decodes to -1 = "no override", keeping old saves valid without a
    // version bump). MH = reserved[0], OH = reserved[1].
    state.reserved[0] = (uint32_t)((int32_t)g_sheatheMH + 1);
    state.reserved[1] = (uint32_t)((int32_t)g_sheatheOH + 1);
    // Barber (player base-model customization) rides in the v6 reserved block so no
    // version bump is needed. reserved[2] packs skin/face/hairStyle/hairColor; the
    // low byte of reserved[3] is facialHair and bit 8 is the "barber active" flag.
    // A zero-filled legacy file therefore decodes to active=0 = no barber.
    state.reserved[2] = BarberPackBytes();
    state.reserved[3] = (uint32_t)g_barberFacial | (g_barberActive ? 0x100u : 0u);

    FILE* f = nullptr;
    if (fopen_s(&f, path, "wb") == 0 && f) {
        fwrite(&state, sizeof(PersistentMorphState), 1, f);
        fclose(f);
    }
}

void SaveFullState(uint64_t guid) {
    PurgeLegacyGlobalStateFiles();
    if (guid == 0) return;

    char path[MAX_PATH];
    GetStateFilePath(guid, path, sizeof(path));
    SaveToPath(path);
}

void LoadFullState(uint64_t guid) {
    PurgeLegacyGlobalStateFiles();
    if (guid == 0) {
        UpdateHasMorph();
        return;
    }

    g_morphDisplay = 0;
    g_morphScale = 0.0f;
    g_morphEnchantMH = 0;
    g_morphEnchantOH = 0;
    g_morphTitle = 0;
    memset(g_morphItems, 0, sizeof(g_morphItems));
    g_morphMount = 0;
    ColorEngine::ItemRetexClear();
    memset(g_slotRetexFrom, 0, sizeof(g_slotRetexFrom));
    memset(g_slotTintFrom,  0, sizeof(g_slotTintFrom));
    memset(g_slotRetexTo,   0, sizeof(g_slotRetexTo));
    memset(g_slotTintApplied, 0, sizeof(g_slotTintApplied));
    memset(g_skinToItem, 0, sizeof(g_skinToItem));
    memset(g_skinTint,   0, sizeof(g_skinTint));
    memset(g_skinAppliedTo, 0, sizeof(g_skinAppliedTo));
    g_hasSkin = false;
    // Barber: clear for this character. Re-captured fresh from the descriptor the
    // first time it stamps, so "Reset" restores the true server look every login.
    g_barberActive = false;
    g_barberOrigSaved = false;
    g_barberSkin = g_barberFace = g_barberHair = g_barberHairColor = g_barberFacial = 0;
    ClearBarberTintMirror();   // drop the previous toon's recolor params on toon switch
    // No state file => no sheath override for this character (avoid leaking the
    // previous character's sheath while switching toons within one client session).
    InterlockedExchange(&g_sheatheMH, -1);
    InterlockedExchange(&g_sheatheOH, -1);
    ClearSpellMorphs();

    char path[MAX_PATH];
    GetStateFilePath(guid, path, sizeof(path));

    FILE* f = nullptr;
    if (fopen_s(&f, path, "rb") == 0 && f) {
        PersistentMorphState state = {};
        bool loaded = false;
        if (fread(&state, sizeof(PersistentMorphState), 1, f) == 1 &&
            state.magic == STATE_FILE_MAGIC &&
            state.version == STATE_FILE_VERSION) {
                g_morphDisplay = state.morphDisplay;
                g_morphScale = state.morphScale;
                g_morphMount = state.morphMount;
                g_morphEnchantMH = state.morphEnchantMH;
                g_morphEnchantOH = state.morphEnchantOH;
                g_morphTitle = state.morphTitle;
                memcpy(g_morphItems, state.morphItems, sizeof(g_morphItems));
                memcpy(g_skinToItem, state.skinToItem, sizeof(g_skinToItem));
                memcpy(g_skinTint,   state.skinTint,   sizeof(g_skinTint));
                memcpy(g_skinAppliedTo, state.skinAppliedTo, sizeof(g_skinAppliedTo));
                // Restore sheath overrides (see SaveToPath for the +1 bias). Set the
                // globals NOW, before the first frame, so the GetSheatheType hook
                // returns the saved position from the very first weapon attach.
                InterlockedExchange(&g_sheatheMH, (LONG)((int32_t)state.reserved[0] - 1));
                InterlockedExchange(&g_sheatheOH, (LONG)((int32_t)state.reserved[1] - 1));
                // Barber (see SaveToPath): reserved[2] = packed skin/face/hair/haircolor,
                // reserved[3] low byte = facialHair, bit 8 = active flag.
                if (state.reserved[3] & 0x100u) {
                    g_barberActive    = true;
                    g_barberSkin      = (uint8_t)(state.reserved[2] & 0xFF);
                    g_barberFace      = (uint8_t)((state.reserved[2] >> 8) & 0xFF);
                    g_barberHair      = (uint8_t)((state.reserved[2] >> 16) & 0xFF);
                    g_barberHairColor = (uint8_t)((state.reserved[2] >> 24) & 0xFF);
                    g_barberFacial    = (uint8_t)(state.reserved[3] & 0xFF);
                }
                // Barber free-RGB recolor params live in a sidecar (the reserved[] block is
                // full). Load them into the live mirror so an in-world save rewrites every
                // region, and so the look is self-consistent before the addon re-pushes.
                {
                    SlotSkinTint bt[4] = {};
                    if (ReadBarberTintFileForGuid(guid, bt)) memcpy(g_barberTint, bt, sizeof(g_barberTint));
                }
                size_t pairCount = (size_t)state.spellMorphCount;
                if (pairCount > MAX_PERSISTED_SPELL_MORPHS) pairCount = MAX_PERSISTED_SPELL_MORPHS;
                ImportSpellMorphPairs(state.spellMorphs, pairCount);
                UpdateHasMorph();
                UpdateHasSkin();
                Log("Loaded state from %s (display=%u mount=%u)",
                    path, g_morphDisplay, g_morphMount);

                // PUSH STATE TO LUA FOR RECOVERY (in case SavedVariables/WTF was wiped)
                if (FrameScript_Execute) {
                    char stateBuf[8192];
                    int pos = sprintf_s(stateBuf, sizeof(stateBuf),
                        "TRANSMORPHER_DLL_STATE = { morph=%u, scale=%.2f, mount=%u, emh=%u, eoh=%u, title=%u, items={}, spells={} }; ",
                        g_morphDisplay, g_morphScale, g_morphMount, g_morphEnchantMH, g_morphEnchantOH, g_morphTitle);

                    for (int s = 1; s <= 19; s++) {
                        if (g_morphItems[s] > 0) {
                            uint32_t itId = (g_morphItems[s] == HIDDEN_SENTINEL) ? 0 : g_morphItems[s];
                            pos += sprintf_s(stateBuf + pos, sizeof(stateBuf) - pos,
                                "TRANSMORPHER_DLL_STATE.items[%d] = %u; ", s, itId);
                        }
                    }
                    for (size_t i = 0; i < pairCount && pos > 0 && pos < (int)sizeof(stateBuf) - 64; ++i) {
                        pos += sprintf_s(stateBuf + pos, sizeof(stateBuf) - pos,
                            "TRANSMORPHER_DLL_STATE.spells[%u] = %u; ",
                            state.spellMorphs[i].sourceSpellId, state.spellMorphs[i].targetSpellId);
                    }
                    FrameScript_Execute(stateBuf, "Transmorpher", 0);
                }
                loaded = true;
        }
        if (!loaded) {
            fseek(f, 0, SEEK_SET);
            PersistentMorphStateV5 v5 = {};
            if (fread(&v5, sizeof(v5), 1, f) == 1 &&
                v5.magic == STATE_FILE_MAGIC && v5.version == 5) {
                g_morphDisplay = v5.morphDisplay;
                g_morphScale = v5.morphScale;
                g_morphMount = v5.morphMount;
                g_morphEnchantMH = v5.morphEnchantMH;
                g_morphEnchantOH = v5.morphEnchantOH;
                g_morphTitle = v5.morphTitle;
                memcpy(g_morphItems, v5.morphItems, sizeof(g_morphItems));
                memcpy(g_skinToItem, v5.skinToItem, sizeof(g_skinToItem));
                memcpy(g_skinTint,   v5.skinTint,   sizeof(g_skinTint));
                memset(g_skinAppliedTo, 0, sizeof(g_skinAppliedTo));
                InterlockedExchange(&g_sheatheMH, (LONG)((int32_t)v5.reserved[0] - 1));
                InterlockedExchange(&g_sheatheOH, (LONG)((int32_t)v5.reserved[1] - 1));
                size_t pairCount = (size_t)v5.spellMorphCount;
                if (pairCount > MAX_PERSISTED_SPELL_MORPHS) pairCount = MAX_PERSISTED_SPELL_MORPHS;
                ImportSpellMorphPairs(v5.spellMorphs, pairCount);
                UpdateHasMorph();
                UpdateHasSkin();
                SaveFullState(guid);
                Log("Loaded v5 state from %s (upgraded to v6)", path);
                loaded = true;
            }
        }
        if (!loaded) {
            // v4 fallback: the legacy SlotSkinTint was 38 bytes (no post-effect
            // fields). Re-read with the v4 struct and upgrade each tint entry to
            // the v5 layout (50 bytes) with neutral defaults for the new fields.
            fseek(f, 0, SEEK_SET);
            PersistentMorphStateV4 v4 = {};
            if (fread(&v4, sizeof(v4), 1, f) == 1 &&
                v4.magic == STATE_FILE_MAGIC && v4.version == 4) {
                g_morphDisplay = v4.morphDisplay;
                g_morphScale = v4.morphScale;
                g_morphMount = v4.morphMount;
                g_morphEnchantMH = v4.morphEnchantMH;
                g_morphEnchantOH = v4.morphEnchantOH;
                g_morphTitle = v4.morphTitle;
                memcpy(g_morphItems, v4.morphItems, sizeof(v4.morphItems));
                memcpy(g_skinToItem, v4.skinToItem, sizeof(v4.skinToItem));
                for (int s = 0; s < 20; ++s) UpgradeV4TintToV5(&v4.skinTint[s], &g_skinTint[s]);
                InterlockedExchange(&g_sheatheMH, (LONG)((int32_t)v4.reserved[0] - 1));
                InterlockedExchange(&g_sheatheOH, (LONG)((int32_t)v4.reserved[1] - 1));
                size_t pairCount = (size_t)v4.spellMorphCount;
                if (pairCount > MAX_PERSISTED_SPELL_MORPHS) pairCount = MAX_PERSISTED_SPELL_MORPHS;
                ImportSpellMorphPairs(v4.spellMorphs, pairCount);
                UpdateHasMorph();
                UpdateHasSkin();
                Log("Loaded v4 state from %s (upgraded to v6)", path);
                // Resave in the new format so we don't pay the upgrade cost on
                // every load. The legacy file is consumed; the next save is v6.
                SaveFullState(guid);
                loaded = true;
            }
        }
        if (!loaded) {
            fseek(f, 0, SEEK_SET);
            PersistentMorphStateV2 stateV2 = {};
            if (fread(&stateV2, sizeof(PersistentMorphStateV2), 1, f) == 1 &&
                stateV2.magic == STATE_FILE_MAGIC && stateV2.version == 2) {
                g_morphDisplay = stateV2.morphDisplay;
                g_morphScale = stateV2.morphScale;
                g_morphMount = stateV2.morphMount;
                g_morphEnchantMH = stateV2.morphEnchantMH;
                g_morphEnchantOH = stateV2.morphEnchantOH;
                g_morphTitle = stateV2.morphTitle;
                memcpy(g_morphItems, stateV2.morphItems, sizeof(g_morphItems));
                ClearSpellMorphs();
                SaveFullState(guid);
                UpdateHasMorph();
            }
        }
        fclose(f);
    } else {
        char legacyPath[MAX_PATH];
        GetLegacyStateFilePath(guid, legacyPath, sizeof(legacyPath));
        if (fopen_s(&f, legacyPath, "rb") == 0 && f) {
            PersistentMorphState state = {};
            bool loaded = false;
            if (fread(&state, sizeof(PersistentMorphState), 1, f) == 1 &&
                state.magic == STATE_FILE_MAGIC && state.version == STATE_FILE_VERSION) {
                    g_morphDisplay = state.morphDisplay;
                    g_morphScale = state.morphScale;
                    g_morphMount = state.morphMount;
                    g_morphEnchantMH = state.morphEnchantMH;
                    g_morphEnchantOH = state.morphEnchantOH;
                    g_morphTitle = state.morphTitle;
                    memcpy(g_morphItems, state.morphItems, sizeof(g_morphItems));
                    memcpy(g_skinToItem, state.skinToItem, sizeof(g_skinToItem));
                    memcpy(g_skinTint,   state.skinTint,   sizeof(g_skinTint));
                    memcpy(g_skinAppliedTo, state.skinAppliedTo, sizeof(g_skinAppliedTo));
                    size_t pairCount = (size_t)state.spellMorphCount;
                    if (pairCount > MAX_PERSISTED_SPELL_MORPHS) pairCount = MAX_PERSISTED_SPELL_MORPHS;
                    ImportSpellMorphPairs(state.spellMorphs, pairCount);
                    SaveFullState(guid);
                    DeleteFileA(legacyPath);
                    UpdateHasMorph();
                    Log("Migrated legacy state to %s", path);
                    loaded = true;
            }
            if (!loaded) {
                fseek(f, 0, SEEK_SET);
                PersistentMorphStateV5 v5 = {};
                if (fread(&v5, sizeof(v5), 1, f) == 1 &&
                    v5.magic == STATE_FILE_MAGIC && v5.version == 5) {
                    g_morphDisplay = v5.morphDisplay;
                    g_morphScale = v5.morphScale;
                    g_morphMount = v5.morphMount;
                    g_morphEnchantMH = v5.morphEnchantMH;
                    g_morphEnchantOH = v5.morphEnchantOH;
                    g_morphTitle = v5.morphTitle;
                    memcpy(g_morphItems, v5.morphItems, sizeof(g_morphItems));
                    memcpy(g_skinToItem, v5.skinToItem, sizeof(g_skinToItem));
                    memcpy(g_skinTint,   v5.skinTint,   sizeof(g_skinTint));
                    memset(g_skinAppliedTo, 0, sizeof(g_skinAppliedTo));
                    size_t pairCount = (size_t)v5.spellMorphCount;
                    if (pairCount > MAX_PERSISTED_SPELL_MORPHS) pairCount = MAX_PERSISTED_SPELL_MORPHS;
                    ImportSpellMorphPairs(v5.spellMorphs, pairCount);
                    SaveFullState(guid);
                    DeleteFileA(legacyPath);
                    UpdateHasMorph();
                    UpdateHasSkin();
                    Log("Migrated legacy v5 state to v6 at %s", path);
                    loaded = true;
                }
            }
            if (!loaded) {
                fseek(f, 0, SEEK_SET);
                PersistentMorphStateV4 v4 = {};
                if (fread(&v4, sizeof(v4), 1, f) == 1 &&
                    v4.magic == STATE_FILE_MAGIC && v4.version == 4) {
                    g_morphDisplay = v4.morphDisplay;
                    g_morphScale = v4.morphScale;
                    g_morphMount = v4.morphMount;
                    g_morphEnchantMH = v4.morphEnchantMH;
                    g_morphEnchantOH = v4.morphEnchantOH;
                    g_morphTitle = v4.morphTitle;
                    memcpy(g_morphItems, v4.morphItems, sizeof(v4.morphItems));
                    memcpy(g_skinToItem, v4.skinToItem, sizeof(v4.skinToItem));
                    for (int s = 0; s < 20; ++s) UpgradeV4TintToV5(&v4.skinTint[s], &g_skinTint[s]);
                    size_t pairCount = (size_t)v4.spellMorphCount;
                    if (pairCount > MAX_PERSISTED_SPELL_MORPHS) pairCount = MAX_PERSISTED_SPELL_MORPHS;
                    ImportSpellMorphPairs(v4.spellMorphs, pairCount);
                    SaveFullState(guid);
                    DeleteFileA(legacyPath);
                    UpdateHasMorph();
                    UpdateHasSkin();
                    Log("Migrated legacy v4 state to v6 at %s", path);
                    loaded = true;
                }
            }
            if (!loaded) {
                fseek(f, 0, SEEK_SET);
                PersistentMorphStateV2 stateV2 = {};
                if (fread(&stateV2, sizeof(PersistentMorphStateV2), 1, f) == 1 &&
                    stateV2.magic == STATE_FILE_MAGIC && stateV2.version == 2) {
                    g_morphDisplay = stateV2.morphDisplay;
                    g_morphScale = stateV2.morphScale;
                    g_morphMount = stateV2.morphMount;
                    g_morphEnchantMH = stateV2.morphEnchantMH;
                    g_morphEnchantOH = stateV2.morphEnchantOH;
                    g_morphTitle = stateV2.morphTitle;
                    memcpy(g_morphItems, stateV2.morphItems, sizeof(g_morphItems));
                    ClearSpellMorphs();
                    SaveFullState(guid);
                    DeleteFileA(legacyPath);
                    UpdateHasMorph();
                }
            }
            fclose(f);
        }
    }
    UpdateHasMorph();
    UpdateHasSkin();
}

// Read a character's persisted morph WITHOUT touching the in-world globals.
// Used by the glue character-select screen (a different render path that has no
// addon and no live player) to morph each doll by its GUID. Fills the creature
// display id + per-slot item ids (1..19). Returns true if a morph file existed.
bool ReadMorphFileForGuid(uint64_t guid, uint32_t* outDisplay, uint32_t outItems[20]) {
    if (outDisplay) *outDisplay = 0;
    if (outItems) memset(outItems, 0, sizeof(uint32_t) * 20);
    if (guid == 0) return false;

    char path[MAX_PATH];
    GetStateFilePath(guid, path, sizeof(path));
    FILE* f = nullptr;
    if (fopen_s(&f, path, "rb") != 0 || !f) return false;

    bool ok = false;
    PersistentMorphState state = {};
    if (fread(&state, sizeof(state), 1, f) == 1 &&
        state.magic == STATE_FILE_MAGIC && state.version == STATE_FILE_VERSION) {
        if (outDisplay) *outDisplay = state.morphDisplay;
        if (outItems) memcpy(outItems, state.morphItems, sizeof(uint32_t) * 20);
        ok = true;
    } else {
        fseek(f, 0, SEEK_SET);
        PersistentMorphStateV5 v5 = {};
        if (fread(&v5, sizeof(v5), 1, f) == 1 &&
            v5.magic == STATE_FILE_MAGIC && v5.version == 5) {
            if (outDisplay) *outDisplay = v5.morphDisplay;
            if (outItems) memcpy(outItems, v5.morphItems, sizeof(uint32_t) * 20);
            ok = true;
        } else {
        fseek(f, 0, SEEK_SET);
        PersistentMorphStateV4 v4 = {};
        if (fread(&v4, sizeof(v4), 1, f) == 1 &&
            v4.magic == STATE_FILE_MAGIC && v4.version == 4) {
            if (outDisplay) *outDisplay = v4.morphDisplay;
            if (outItems) memcpy(outItems, v4.morphItems, sizeof(uint32_t) * 20);
            ok = true;
        } else {
            fseek(f, 0, SEEK_SET);
            PersistentMorphStateV2 v2 = {};
            if (fread(&v2, sizeof(v2), 1, f) == 1 &&
                v2.magic == STATE_FILE_MAGIC && v2.version == 2) {
                if (outDisplay) *outDisplay = v2.morphDisplay;
                if (outItems) memcpy(outItems, v2.morphItems, sizeof(uint32_t) * 20);
                ok = true;
            }
        }
        }
    }
    fclose(f);
    return ok;
}

// Read the per-slot skin (donor item id) + tint struct for a character, without
// touching the live in-world state. Called by the glue character-select path
// after the doll is built, so a saved skin is rendered on the doll. Returns
// true if a v4 state file with skin data existed; outSkin and outTint are
// zero-filled otherwise (no skin).
bool ReadSkinFileForGuid(uint64_t guid, uint32_t outSkin[20], SlotSkinTint outTint[20]) {
    if (outSkin) memset(outSkin, 0, sizeof(uint32_t) * 20);
    if (outTint) memset(outTint, 0, sizeof(SlotSkinTint) * 20);
    if (guid == 0) return false;

    char path[MAX_PATH];
    GetStateFilePath(guid, path, sizeof(path));
    FILE* f = nullptr;
    if (fopen_s(&f, path, "rb") != 0 || !f) return false;

    bool ok = false;
    PersistentMorphState state = {};
    if (fread(&state, sizeof(state), 1, f) == 1 &&
        state.magic == STATE_FILE_MAGIC && state.version == STATE_FILE_VERSION) {
        if (outSkin) memcpy(outSkin, state.skinToItem, sizeof(uint32_t) * 20);
        if (outTint) memcpy(outTint, state.skinTint,   sizeof(SlotSkinTint) * 20);
        ok = true;
    } else {
        fseek(f, 0, SEEK_SET);
        PersistentMorphStateV5 v5 = {};
        if (fread(&v5, sizeof(v5), 1, f) == 1 &&
            v5.magic == STATE_FILE_MAGIC && v5.version == 5) {
            if (outSkin) memcpy(outSkin, v5.skinToItem, sizeof(uint32_t) * 20);
            if (outTint) memcpy(outTint, v5.skinTint,   sizeof(SlotSkinTint) * 20);
            ok = true;
        } else {
        fseek(f, 0, SEEK_SET);
        PersistentMorphStateV4 v4 = {};
        if (fread(&v4, sizeof(v4), 1, f) == 1 &&
            v4.magic == STATE_FILE_MAGIC && v4.version == 4) {
            if (outSkin) memcpy(outSkin, v4.skinToItem, sizeof(uint32_t) * 20);
            for (int s = 0; s < 20; ++s) UpgradeV4TintToV5(&v4.skinTint[s], &outTint[s]);
            ok = true;
        }
        }
    }
    fclose(f);
    return ok;
}

// Read a character's persisted BARBER customization by GUID, without touching the
// in-world globals. Used by the glue character-select hook so the doll shows the
// same skin/face/hair the user set in the world. Returns true if barber was active
// in the saved state; out bytes are zero-filled otherwise.
bool ReadBarberFileForGuid(uint64_t guid, uint8_t* outSkin, uint8_t* outFace,
                           uint8_t* outHair, uint8_t* outHairColor, uint8_t* outFacial) {
    if (outSkin) *outSkin = 0; if (outFace) *outFace = 0; if (outHair) *outHair = 0;
    if (outHairColor) *outHairColor = 0; if (outFacial) *outFacial = 0;
    if (guid == 0) return false;
    char path[MAX_PATH];
    GetStateFilePath(guid, path, sizeof(path));
    FILE* f = nullptr;
    if (fopen_s(&f, path, "rb") != 0 || !f) return false;
    bool active = false;
    PersistentMorphState state = {};
    if (fread(&state, sizeof(state), 1, f) == 1 &&
        state.magic == STATE_FILE_MAGIC && state.version == STATE_FILE_VERSION &&
        (state.reserved[3] & 0x100u)) {
        if (outSkin)      *outSkin      = (uint8_t)(state.reserved[2] & 0xFF);
        if (outFace)      *outFace      = (uint8_t)((state.reserved[2] >> 8) & 0xFF);
        if (outHair)      *outHair      = (uint8_t)((state.reserved[2] >> 16) & 0xFF);
        if (outHairColor) *outHairColor = (uint8_t)((state.reserved[2] >> 24) & 0xFF);
        if (outFacial)    *outFacial    = (uint8_t)(state.reserved[3] & 0xFF);
        active = true;
    }
    fclose(f);
    return active;
}

// ---- Barber free-RGB recolor persistence (per-guid sidecar) --------------------
// The colors can't ride in the main state file (its reserved[] block is full) and the
// addon isn't running at the glue screen to push them, so we keep a tiny sidecar file
// of the four region tint params and replay it onto the character-select doll.
#pragma pack(push, 1)
struct BarberTintFile {
    uint32_t     magic;        // 'BTNT'
    uint32_t     version;      // 1
    SlotSkinTint region[4];    // 0 skin, 1 face, 2 hair, 3 facial
};
#pragma pack(pop)
static const uint32_t BARBER_TINT_MAGIC   = 0x544E5442u;  // 'BTNT'
static const uint32_t BARBER_TINT_VERSION = 1u;

static void GetBarberTintFilePath(uint64_t guid, char* out, size_t size) {
    EnsureStateFolders();
    if (guid == 0) { if (size) out[0] = '\0'; return; }
    char bucket[3] = {0};
    sprintf_s(bucket, sizeof(bucket), "%02X", (unsigned)(guid & 0xFF));
    char bucketDir[MAX_PATH];
    sprintf_s(bucketDir, sizeof(bucketDir), "%s\\state\\chars\\%s", g_dllDir, bucket);
    CreateDirectoryA(bucketDir, NULL);
    sprintf_s(out, size, "%s\\transmorpher_barbertint_%llu.dat", bucketDir, guid);
}

void SetBarberTintRegion(int region, const SlotSkinTint* rec) {
    if (region < 0 || region > 3) return;
    if (rec) g_barberTint[region] = *rec;
    else     memset(&g_barberTint[region], 0, sizeof(SlotSkinTint));
}

void ClearBarberTintMirror() {
    memset(g_barberTint, 0, sizeof(g_barberTint));
}

void SaveBarberTintFile(uint64_t guid) {
    if (guid == 0) return;
    char path[MAX_PATH];
    GetBarberTintFilePath(guid, path, sizeof(path));
    if (!path[0]) return;
    bool any = false;
    for (int i = 0; i < 4; ++i) if (g_barberTint[i].enabled) { any = true; break; }
    if (!any) { DeleteFileA(path); return; }   // cleared look -> no stale sidecar
    BarberTintFile f = {};
    f.magic = BARBER_TINT_MAGIC;
    f.version = BARBER_TINT_VERSION;
    memcpy(f.region, g_barberTint, sizeof(g_barberTint));
    FILE* fp = nullptr;
    if (fopen_s(&fp, path, "wb") == 0 && fp) {
        fwrite(&f, sizeof(f), 1, fp);
        fclose(fp);
    }
}

bool ReadBarberTintFileForGuid(uint64_t guid, SlotSkinTint outTint[4]) {
    if (outTint) memset(outTint, 0, sizeof(SlotSkinTint) * 4);
    if (guid == 0 || !outTint) return false;
    char path[MAX_PATH];
    GetBarberTintFilePath(guid, path, sizeof(path));
    if (!path[0]) return false;
    FILE* fp = nullptr;
    if (fopen_s(&fp, path, "rb") != 0 || !fp) return false;
    BarberTintFile f = {};
    bool ok = false;
    if (fread(&f, sizeof(f), 1, fp) == 1 &&
        f.magic == BARBER_TINT_MAGIC && f.version == BARBER_TINT_VERSION) {
        memcpy(outTint, f.region, sizeof(SlotSkinTint) * 4);
        for (int i = 0; i < 4; ++i) if (outTint[i].enabled) { ok = true; break; }
    }
    fclose(fp);
    return ok;
}

static void CaptureOriginalsFromPlayer(WowObject* p, bool force) {
    if (!p || !p->descriptors) return;
    if (!force && g_saved) return;
    uint8_t* desc = (uint8_t*)p->descriptors;
    // UNIT_FIELD_NATIVEDISPLAYID is offset 0x110 (index 0x44 * 4)
    uint32_t currentDisp = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
    
    // GHOST PROTECTION: Never capture originals if the player is a ghost
    // Ghost IDs: 16543 (Male), 16544 (Female).
    if (currentDisp == 16543 || currentDisp == 16544 || currentDisp == 0) return;

    // CAPTURE BASE RACE: We always capture the NATIVE display ID (our true race)
    // so that we never get stuck in a shapeshift form visual (Moonkin/Bear/etc).
    g_origDisplay = currentDisp;
    
    // Prevent capturing "polluted" scale while mounted
    if (g_luaMounted == 0) {
        g_origScale = *(float*)(desc + 0x10);
        if (g_origScale < 0.1f || g_origScale > 10.0f) g_origScale = 1.0f;
    } else if (g_origScale < 0.1f || g_origScale > 10.0f) {
        g_origScale = 1.0f;
    }
    
    for (int s = 1; s <= 19; s++) {
        uint32_t off = GetVisibleItemField(s);
        if (off) g_origItems[s] = *(uint32_t*)(desc + off);
    }
    
    uint32_t offMH = GetVisibleEnchantField(16);
    uint32_t offOH = GetVisibleEnchantField(17);
    if (offMH) g_origEnchantMH = *(uint32_t*)(desc + offMH);
    if (offOH) g_origEnchantOH = *(uint32_t*)(desc + offOH);
    
    g_origTitle = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
    g_saved = true;
}

static void SaveOriginals(WowObject* p) {
    CaptureOriginalsFromPlayer(p, false);
}

void PrimeOriginalState(WowObject* player) {
    g_saved = false;
    CaptureOriginalsFromPlayer(player, true);
}

static void RefreshOriginals(WowObject* p) {
    if (!p || !p->descriptors || !g_saved) return;
    uint8_t* desc = (uint8_t*)p->descriptors;

    if (g_morphDisplay == 0) {
        // Always refresh from NATIVE ID to prevent capturing temporary forms as originals
        uint32_t currentDisp = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
        // Only refresh if NOT a ghost
        if (currentDisp != 16543 && currentDisp != 16544 && currentDisp != 0) {
            g_origDisplay = currentDisp;
        }
    }
    if (g_morphMount == 0) g_origMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
    if (g_morphScale <= 0.0f && g_luaMounted == 0) {
        float cur = *(float*)(desc + 0x10);
        if (cur >= 0.1f && cur <= 10.0f) g_origScale = cur;
    }
    
    for (int s = 1; s <= 19; s++) {
        if (g_morphItems[s] == 0) {
            uint32_t off = GetVisibleItemField(s);
            if (off) g_origItems[s] = *(uint32_t*)(desc + off);
        }
    }
    
    if (g_morphEnchantMH == 0) {
        uint32_t off = GetVisibleEnchantField(16);
        if (off) g_origEnchantMH = *(uint32_t*)(desc + off);
    }
    if (g_morphEnchantOH == 0) {
        uint32_t off = GetVisibleEnchantField(17);
        if (off) g_origEnchantOH = *(uint32_t*)(desc + off);
    }
    
    if (g_morphTitle == 0) {
        g_origTitle = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
    }
}

// Force the engine to RE-ATTACH a visible-item slot from the morph WITHOUT a relog. The body
// composite re-syncs armor slots (0..13) on every rebuild, but the WEAPON entries (engine slots
// 15=MH / 16=OH / 17=Ranged) keep their cached item and never re-sync from VISIBLE_ITEM — that is
// the "warglaives / some weapons need a relog to update" bug. The engine's component cache lives
// at *(unit+0x1008)+0x21c, indexed by EQUIPMENT_SLOT, stride 8; entry[0] is the attached ITEM id
// and a NEGATIVE value marks the slot PENDING so RefreshAllComponentItems (0x6E09E0) detaches and
// re-attaches it (RE-verified at 0x6E09E0 / 0x6E08C0 / 0x758E50, item store 0xC5D828; the dump
// confirmed entry[15]=[16]=32837 = the worn Warglaives). morpherSlot is the Transmorpher logical
// slot (1..19) -> engine EQUIPMENT_SLOT via the same MAP the descriptor uses. We only mark a slot
// when the attached item actually differs from the target, so a redundant re-stamp never flickers.
void ForceRefreshComponents(WowObject* player);   // fwd: RefreshAllComponentItems @0x6E09E0

// --- TEMP weapon diagnostic: plain file next to wow.exe (NOT TSM_logs), bounded. -----------
static volatile LONG g_wdiagLines = 0;
static void WDiag(const char* fmt, ...) {
    if (g_wdiagLines >= 400) return;
    char body[400]; va_list ap; va_start(ap, fmt);
    _vsnprintf_s(body, sizeof(body), _TRUNCATE, fmt, ap); va_end(ap);
    __try {
        char path[MAX_PATH];
        if (!GetModuleFileNameA(NULL, path, MAX_PATH)) return;
        char* slash = strrchr(path, '\\'); if (!slash) return;
        strcpy_s(slash + 1, MAX_PATH - (size_t)(slash + 1 - path), "transmorpher_scope_diag.txt");
        FILE* f = nullptr;
        if (fopen_s(&f, path, "a") == 0 && f) { fprintf(f, "WDIAG %s\n", body); fclose(f); InterlockedIncrement(&g_wdiagLines); }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}
static int32_t SafeReadInt(WowObject* player, uint32_t off) {
    if (!player) return -999;
    __try { return *(int32_t*)((uint8_t*)player + off); } __except (EXCEPTION_EXECUTE_HANDLER) { return -999; }
}
// Read the raw engine component entry for a Transmorpher slot (item id; negative = pending).
static int32_t ReadCompEntry(WowObject* player, int morpherSlot) {
    static const int MAP[20] = { 0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18 };
    if (!player || morpherSlot < 1 || morpherSlot > 19) return 0x7FFFFFFF;
    __try {
        uint8_t* mgr = *(uint8_t**)((uint8_t*)player + 0x1008);
        if (!mgr || (uintptr_t)mgr < 0x10000) return 0x7FFFFFFF;
        return *(int32_t*)(mgr + MAP[morpherSlot] * 8 + 0x21c);
    } __except (EXCEPTION_EXECUTE_HANDLER) { return 0x7FFFFFFF; }
}

// Force a visible-item slot to PENDING so the engine re-attaches its model. The engine syncs
// the component entry to the morphed item as a POSITIVE ("already attached") value WITHOUT
// rebuilding the 3D model, so the new weapon never appears until a relog. Writing the NEGATIVE
// of the item id flags the slot pending; RefreshAllComponentItems then detaches the stale model
// and attaches the new one. itemId 0 = hidden (leave the engine's own detach to run).
bool MarkVisibleItemSlotPending(WowObject* player, int morpherSlot, uint32_t itemId) {
    if (!player || morpherSlot < 1 || morpherSlot > 19 || itemId == 0) return false;
    static const int MAP[20] = { 0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18 };
    const int eng = MAP[morpherSlot];
    __try {
        uint8_t* mgr = *(uint8_t**)((uint8_t*)player + 0x1008);
        if (!mgr || (uintptr_t)mgr < 0x10000) return false;
        int32_t* entry = (int32_t*)(mgr + eng * 8 + 0x21c);
        *entry = -(int32_t)itemId;   // ALWAYS pending -> guarantees a fresh detach+re-attach
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    return true;
}

void ReStampWeapons(WowObject* player) {
    if (!player || !player->descriptors) return;
    uint8_t* desc = (uint8_t*)player->descriptors;
    for (int s = 16; s <= 18; s++) {
        if (g_morphItems[s] > 0) {
            uint32_t off = GetVisibleItemField(s);
            if (off) {
                uint32_t target = (g_morphItems[s] == HIDDEN_SENTINEL) ? 0 : g_morphItems[s];
                *(uint32_t*)(desc + off) = target;
            }
        }
    }
    if (g_morphEnchantMH > 0) {
        uint32_t off = GetVisibleEnchantField(16);
        if (off) *(uint32_t*)(desc + off) = g_morphEnchantMH;
    }
    if (g_morphEnchantOH > 0) {
        uint32_t off = GetVisibleEnchantField(17);
        if (off) *(uint32_t*)(desc + off) = g_morphEnchantOH;
    }
}

// Force the morphed WEAPON slots to re-attach their model NOW (no relog). Called only on a real
// change signal (g_weaponRefreshTicks), never the per-tick maintenance, so there is no flicker.
void ForceWeaponReattach(WowObject* player) {
    if (!player || !player->descriptors) return;
    bool any = false;
    for (int s = 16; s <= 18; s++) {
        if (g_morphItems[s] > 0 && g_morphItems[s] != HIDDEN_SENTINEL) {
            if (MarkVisibleItemSlotPending(player, s, g_morphItems[s])) any = true;
        }
    }
    if (any) {
        ForceRefreshComponents(player);
        WDiag("ForceWeaponReattach MH=%d OH=%d Ranged=%d sheathe=%d",
              ReadCompEntry(player, 16), ReadCompEntry(player, 17), ReadCompEntry(player, 18),
              SafeReadInt(player, 0xb5c));
    }
}

// IsTitleKnown and SetTitleKnown are defined in Utils.cpp

bool ApplyMorphState(WowObject* player) {
    if (!player || !player->descriptors) return false;
    uint8_t* desc = (uint8_t*)player->descriptors;
    bool changed = false;

    // VEHICLE GUARD (RE-verified, mirrors Lua_UnitInVehicle): the Lua layer already suspends
    // sending while we board a vehicle, but guard the model fields here too so a race (or a
    // vehicle entered without the Lua event, e.g. a forced seat) can never leave us forcing a
    // morph display/scale over the engine's seated model — the cause of the "invisible on a
    // vehicle" bug. Title/items below are model-neutral and stay applied.
    const bool inVehicle = IsUnitInVehicle(player);

    if (!inVehicle && g_morphDisplay > 0) {
        uint32_t current = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
        if (current != g_morphDisplay) {
            // Use SimplyMorpher3's double-update technique for race morphs
            if (IsRaceDisplayID(g_morphDisplay)) {
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = 621;
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = g_morphDisplay;
                
                // Refresh equipment slots
                for (int s = 1; s <= 19; s++) {
                    if (g_morphItems[s] == 0) {
                        uint32_t off = GetVisibleItemField(s);
                        if (off) {
                            uint32_t currentItem = *(uint32_t*)(desc + off);
                            if (currentItem > 0) {
                                *(uint32_t*)(desc + off) = currentItem;
                            }
                        }
                    }
                }
            } else {
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = g_morphDisplay;
            }
            ReapplyActiveBarberTintsForPlayer(player);
            changed = true;
        }
    }

    if (!inVehicle && g_morphScale > 0.01f) {
        float current = *(float*)(desc + 0x10);
        bool skipScaleOverride = false;
        
        // If mounted and target scale is ~1.0, allow WoW's mount scaling (usually 1.0 to 1.25)
        if (g_luaMounted == 1 && g_morphScale > 0.99f && g_morphScale < 1.01f) {
            if (current >= 0.8f && current <= 2.2f) skipScaleOverride = true;
        }

        if (!skipScaleOverride && (current < g_morphScale - 0.001f || current > g_morphScale + 0.001f)) {
            *(float*)(desc + 0x10) = g_morphScale;
            changed = true;
        }
    }

    if (g_morphTitle > 0) {
        uint32_t current = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
        if (current != g_morphTitle) {
            *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = g_morphTitle;
            changed = true;
        }
        if (!IsTitleKnown(player, g_morphTitle)) {
            SetTitleKnown(player, g_morphTitle, true);
            changed = true;
        }
    }

    for (int s = 1; s <= 19; s++) {
        if (g_morphItems[s] > 0) {
            uint32_t off = GetVisibleItemField(s);
            if (off) {
                uint32_t target = (g_morphItems[s] == HIDDEN_SENTINEL) ? 0 : g_morphItems[s];
                uint32_t current = *(uint32_t*)(desc + off);
                if (current != target) {
                    *(uint32_t*)(desc + off) = target;
                    changed = true;
                }
            }
        }
    }

    return changed;
}

void ForceRefreshComponents(WowObject* player);

// Full appearance rebuild that is SAFE for body-armor skins (helmet/shoulder/chest/
// etc). A plain CGUnit_UpdateDisplayInfo reuses the cached, already-composited body
// component textures, so a retex/tint apply OR reset on those slots only "sometimes"
// took (and otherwise needed a relog). This does two things together:
//   1) a display-id bounce (rebuilds the model + most appearance), and
//   2) a visible-item bounce (zero every visible item then restore), which runs the
//      client's equipment-changed composite rebuild and releases the refcounted body
//      component textures so the baked skin is re-composited from scratch.
// Both together make apply AND reset reliable for every slot, no relog. SEH-guarded.
void RefreshPlayerModelFull(WowObject* player) {
    if (!player || !player->descriptors || !CGUnit_UpdateDisplayInfo) return;
    __try {
        uint8_t* d = (uint8_t*)player->descriptors;
        uint32_t cur = *(uint32_t*)(d + UNIT_FIELD_DISPLAYID);
        if (cur != 0) {
            *(uint32_t*)(d + UNIT_FIELD_DISPLAYID) = 621;
            ScopedUpdateDisplayInfo(player, 0);
            ForceRefreshComponents(player);
            *(uint32_t*)(d + UNIT_FIELD_DISPLAYID) = cur;
            ScopedUpdateDisplayInfo(player, 0);
            ForceRefreshComponents(player);
        } else {
            ScopedUpdateDisplayInfo(player, 1);
            ForceRefreshComponents(player);
        }
        uint32_t saved[20] = {0}; bool any = false;
        for (int s = 1; s <= 19; ++s) {
            uint32_t off = GetVisibleItemField(s);
            if (off) { saved[s] = *(uint32_t*)(d + off); if (saved[s]) { *(uint32_t*)(d + off) = 0; any = true; } }
        }
        if (any) {
            ScopedUpdateDisplayInfo(player, 0);
            ForceRefreshComponents(player);
            for (int s = 1; s <= 19; ++s) {
                uint32_t off = GetVisibleItemField(s);
                if (off && saved[s]) *(uint32_t*)(d + off) = saved[s];
            }
            ScopedUpdateDisplayInfo(player, 0);
            ForceRefreshComponents(player);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

// CGUnit_C::RefreshAllComponentItems(this) — the engine's OWN full "re-equip
// EVERYTHING". Verified by disassembly of wow.exe @0x006E09E0 (12340): thiscall(CGUnit*),
// no args. It loops every component slot edi = 0..0x12 (0..18) and, for each, calls the
// per-slot refresh worker @0x006E08C0, which detaches then re-attaches that component or
// weapon — dropping its cached decoded texture/attachment and re-resolving it from the
// (now redirect-free) item display info. CRUCIALLY this covers the WEAPON slots 15/16/17
// (worker special-cases them via the weapon re-attach @0x00720170) and the cloak/back,
// which the OLD path missed.
//
// The previous implementation called CGUnit_C::RefreshComponentItem(0x00723730) for doll
// slots 0..10 only. That helper runs the input through a slot mapper (0x004E7AF0) whose
// jump table NEVER emits the weapon indices 15/16/17 — so weapons (and their glow/particle
// FX) could not be refreshed at all and stayed tinted/reskinned until a relog. This is the
// "helmet/shoulder/cape/weapon don't reset without relog" bug. RefreshAllComponentItems is
// the engine's own equipment-changed refresh, so it re-attaches them exactly like a real
// weapon swap. Self-guarded by 0x007202C0 (no-ops if the model/item data isn't ready), so
// it is safe to call at any time.
typedef void(__thiscall* RefreshAllComponentItems_fn)(void* unit);
void ForceRefreshComponents(WowObject* player) {
    if (!player || !player->descriptors) return;
    RefreshAllComponentItems_fn fn = reinterpret_cast<RefreshAllComponentItems_fn>(0x006E09E0);
    __try { fn(player); } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

// ---- Barber apply --------------------------------------------------------------
// Capture the player's real (server) appearance bytes once per session, so a barber
// reset can restore the exact original look.
static void CaptureBarberOriginal(WowObject* player) {
    if (g_barberOrigSaved || !player || !player->descriptors) return;
    uint8_t* desc = (uint8_t*)player->descriptors;
    __try {
        g_barberOrigBytes  = *(uint32_t*)(desc + PLAYER_FIELD_BYTES);
        g_barberOrigFacial = *(uint8_t*)(desc + PLAYER_FIELD_BYTES2);
        g_barberOrigSaved  = true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

// Write the active barber bytes into the player's PLAYER_BYTES / PLAYER_BYTES_2
// descriptor fields. Returns true if the descriptor actually changed. Optionally
// rebuilds the model so the new skin/face/hair render immediately. A player-clone
// (Copy-Target) takes precedence: when g_morphPlayerBytesActive the clone owns the
// appearance bytes, so barber stays dormant until the clone is dropped.
bool ApplyBarberToPlayer(WowObject* player, bool refresh) {
    if (!player || !player->descriptors || !g_barberActive) return false;
    if (g_morphPlayerBytesActive) return false;
    CaptureBarberOriginal(player);
    uint8_t* desc = (uint8_t*)player->descriptors;
    bool changed = false;
    __try {
        uint32_t want = BarberPackBytes();
        if (*(uint32_t*)(desc + PLAYER_FIELD_BYTES) != want) {
            *(uint32_t*)(desc + PLAYER_FIELD_BYTES) = want; changed = true;
        }
        if (*(uint8_t*)(desc + PLAYER_FIELD_BYTES2) != g_barberFacial) {
            *(uint8_t*)(desc + PLAYER_FIELD_BYTES2) = g_barberFacial; changed = true;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
    if (refresh) RefreshPlayerModelFull(player);
    return changed;
}

struct EffectiveBarberLook {
    int race = 0;
    int sex = 0;
    int classId = 0;
    int skin = 0;
    int face = 0;
    int hair = 0;
    int hairColor = 0;
    int facial = 0;
    uint32_t displayId = 0;
    bool displayResolved = false;
    bool appearanceFromDisplay = false;
};

static bool ResolveEffectiveBarberLook(WowObject* player, int fallbackRace, int fallbackSex, EffectiveBarberLook* out) {
    if (!out) return false;
    *out = EffectiveBarberLook{};
    out->race = fallbackRace;
    out->sex = fallbackSex;

    if (player && player->descriptors) {
        uint8_t* d = (uint8_t*)player->descriptors;
        __try {
            uint32_t live = *(uint32_t*)(d + PLAYER_FIELD_BYTES);
            uint32_t b0 = *(uint32_t*)(d + UNIT_FIELD_BYTES_0);
            out->classId = (int)((b0 >> 8) & 0xFF);
            if (out->race <= 0) out->race = (int)(b0 & 0xFF);
            if (out->sex != 0 && out->sex != 1) out->sex = (int)((b0 >> 16) & 0xFF);
            out->skin      = (int)(live & 0xFF);
            out->face      = (int)((live >> 8) & 0xFF);
            out->hair      = (int)((live >> 16) & 0xFF);
            out->hairColor = (int)((live >> 24) & 0xFF);
            out->facial    = (int)*(uint8_t*)(d + PLAYER_FIELD_BYTES2);

            out->displayId = *(uint32_t*)(d + UNIT_FIELD_DISPLAYID);
            if ((out->displayId == 0 || out->displayId == 621) && g_morphDisplay > 0) out->displayId = g_morphDisplay;
            if (out->displayId == 0) out->displayId = *(uint32_t*)(d + UNIT_FIELD_NATIVEDISPLAYID);
        } __except (EXCEPTION_EXECUTE_HANDLER) { return out->race > 0; }
    }

    if (g_barberActive && !g_morphPlayerBytesActive) {
        out->skin = g_barberSkin;
        out->face = g_barberFace;
        out->hair = g_barberHair;
        out->hairColor = g_barberHairColor;
        out->facial = g_barberFacial;
    }

    if (out->displayId > 0) {
        int dRace = 0, dSex = 0, dSkin = 0, dFace = 0, dHair = 0, dHairColor = 0, dFacial = 0;
        bool fromExtra = false;
        if (ColorEngine::ResolveDisplayCharacterAppearance(out->displayId, &dRace, &dSex,
                &dSkin, &dFace, &dHair, &dHairColor, &dFacial, &fromExtra)) {
            out->race = dRace;
            out->sex = dSex;
            out->displayResolved = true;
            // NPC/humanoid display ids own their appearance through CDIExtra unless a
            // live barber/player-clone override is already stamping PLAYER_BYTES.
            if (fromExtra && !g_barberActive && !g_morphPlayerBytesActive) {
                out->skin = dSkin;
                out->face = dFace;
                out->hair = dHair;
                out->hairColor = dHairColor;
                out->facial = dFacial;
                out->appearanceFromDisplay = true;
            }
        }
    }

    return out->race > 0 && (out->sex == 0 || out->sex == 1);
}

static void ReapplyActiveBarberTintsForPlayer(WowObject* player) {
    bool any = false;
    for (int region = 0; region < 4; ++region) {
        if (g_barberTint[region].enabled) { any = true; break; }
    }
    if (!any) return;

    EffectiveBarberLook look;
    if (!ResolveEffectiveBarberLook(player, 0, 0, &look)) return;
    for (int region = 0; region < 4; ++region) {
        const SlotSkinTint& t = g_barberTint[region];
        if (!t.enabled) continue;
        ColorEngine::SetBarberRegionTint(region, look.race, look.sex, look.classId,
            look.skin, look.face, look.hair, look.hairColor, look.facial,
            true, (int)t.mode, t.r, t.g, t.b, t.r2, t.g2, t.b2,
            (int)t.dir, (int)t.mult, (int)t.glowStr, (int)t.contrast,
            (int)t.span, (int)t.phase, (int)t.brightness, (int)t.saturation, (int)t.hueShift);
    }
}

static bool IsSeparateModelSlot(int slot) {
    return slot == 1 || slot == 3 || slot == 15 || slot == 16 || slot == 17 || slot == 18;
}

static void RefreshTintedModelSlot(int slot, uint32_t itemId) {
    if (!IsSeparateModelSlot(slot) || itemId == 0) return;
    // Force a hard model re-stream: CGUnit_UpdateDisplayInfo(player, 1) disposes
    // the current CModelView and re-streams the M2 from MPQ. Our decode hook
    // (hkBLPFileLockChain2) re-tints the freshly-loaded BLP using the tint state
    // we just stored in g_itemTintSlots, so weapon color updates without a relog.
    // Do NOT call ColorEngine::ReloadModelTexturesForSlot synchronously here:
    // that disposes the BLP/CFile the engine is still mid-read on (the M2 chunk
    // stream holds an SFile read interface whose vtable-holder is the very
    // object we would invalidate), causing an access violation in the engine's
    // vtable dispatch thunk (ecx+4 was NULL on the resumed stream).
    g_pendingModelTintReload[slot] = itemId;
    g_pendingSkinHardReload = true;
    if (slot >= 16 && slot <= 18) g_weaponRefreshTicks = 2;
}

// Force-flush the originally-equipped items into the visible descriptors and rebuild
// the model. This is the only path that reliably drops a tint/retex baked into the
// object-component attachments (helmet/shoulder/cape/weapon). Merely clearing the
// tint/retex maps and reloading the texture cache is NOT enough: those attachments
// keep holding the old texture object across the refresh. By writing the original
// item id (the one captured at session start — no morph, no skin) into the visible
// descriptor, we force the engine to destroy the current attachment and build a new
// one from a clean BLP. Any active morph is re-stamped on top by the morph system
// (ApplyMorphState / ReStampWeapons), so the morph survives. SEH-guarded.
void ForceFlushOriginalsToVisible(WowObject* player) {
    if (!player || !player->descriptors) return;
    uint8_t* desc = (uint8_t*)player->descriptors;
    __try {
        // Compute the CLEAN re-attach target for each slot. A MORPHED slot must
        // re-attach from its MORPH item (or nothing, if hidden) — NEVER the original.
        // Writing the original into a morphed weapon slot makes the engine attach the
        // original weapon model, which then lingers as a ghost next to the morphed
        // weapon ("Reset All shows 3 weapons / the original while morphed"); a hidden
        // slot would likewise reveal the original. A non-morphed slot re-attaches from
        // the originally-equipped item (the clean, un-tinted base) as before.
        uint32_t target[20] = {0};
        bool touch[20] = {false};
        for (int s = 1; s <= 19; ++s) {
            if (g_morphItems[s] > 0) {
                target[s] = (g_morphItems[s] == HIDDEN_SENTINEL) ? 0 : g_morphItems[s];
                touch[s] = true;                  // morphed (incl. hidden) -> re-attach clean
            } else if (g_origItems[s] > 0) {
                target[s] = g_origItems[s];
                touch[s] = true;                  // plain equipped -> re-attach original
            }
        }
        // Detach the current attachment by writing 0, then re-create it from the clean
        // target. Two writes + a refresh between them is what the engine needs to
        // actually drop the old attachment (one write is a no-op for object components).
        for (int s = 1; s <= 19; ++s) {
            if (!touch[s]) continue;
            uint32_t off = GetVisibleItemField(s);
            if (off) *(uint32_t*)(desc + off) = 0;
        }
        if (CGUnit_UpdateDisplayInfo) {
            ScopedUpdateDisplayInfo(player, 0);
        }
        // Engine's own full re-equip path — detaches every object component, then
        // re-attaches them from the now-zero descriptors, dropping their cached
        // tinted textures in the process.
        ForceRefreshComponents(player);
        for (int s = 1; s <= 19; ++s) {
            if (!touch[s]) continue;
            uint32_t off = GetVisibleItemField(s);
            if (off) *(uint32_t*)(desc + off) = target[s];
        }
        if (CGUnit_UpdateDisplayInfo) {
            ScopedUpdateDisplayInfo(player, 0);
        }
        ForceRefreshComponents(player);
    } __except (EXCEPTION_EXECUTE_HANDLER) {}
}

// Synchronous, self-contained skin reset — fires IMMEDIATELY on the reset command.
// onlySlot == 0 -> every slot (Reset All); 1..19 -> one equipment slot (manual reset).
//
// THE one-for-all fix for the separate-model items (helmet/shoulder/cape/weapon):
// their tint is baked directly into the cached texture object's pixels (the decode
// hook tints in place, and they don't pass through the cache-key redirect the body
// armor uses), so merely dropping the redirect never un-tints them — the engine
// keeps holding the OLD attachment. We instead:
//   (1) clear all tint/retex/persist state (restoring every ItemDisplayInfo to
//       original; the ItemDisplayInfo in memory now points at the donor/original
//       textures, not the tinted ones),
//   (2) ReloadAllTextures() — re-decode every loaded texture from disk with the
//       tint map now empty, so the cached pixels are clean (also captures fresh
//       CTexture objects for the affected model items),
//   (3) reload the live + donor + tint-source textures for each affected slot,
//   (4) ForceFlushOriginalsToVisible — the ROBUST kill: write the originally
//       equipped items (g_origItems[], captured at session start, no morph, no
//       skin) into every visible descriptor with a 0-detach in between, then
//       re-attach. This destroys the old object-component attachment that was
//       holding the tinted texture, and rebuilds a fresh one from the original
//       BLP. The morph system re-stamps morph items on top via ReStampWeapons +
//       the MorphGuard tick, so the morph survives the flush.
// Leaves NO redirects behind, so a later apply starts from a pristine state.
void CleanResetSlots(WowObject* player, int onlySlot) {
    if (!player || !player->descriptors) return;
    const bool all = (onlySlot < 1 || onlySlot > 19);
    const int lo = all ? 1 : onlySlot;
    const int hi = all ? 19 : onlySlot;

    uint32_t visBefore[20] = {0};
    uint32_t retFromBefore[20] = {0};
    uint32_t retToBefore[20] = {0};
    uint32_t tintFromBefore[20] = {0};
    uint8_t* desc = (uint8_t*)player->descriptors;
    for (int s = lo; s <= hi; ++s) {
        retFromBefore[s] = g_slotRetexFrom[s];
        retToBefore[s] = g_slotRetexTo[s];
        tintFromBefore[s] = g_slotTintFrom[s];
        uint32_t off = GetVisibleItemField(s);
        if (off) {
            __try { visBefore[s] = *(uint32_t*)(desc + off); }
            __except (EXCEPTION_EXECUTE_HANDLER) { visBefore[s] = 0; }
        }
    }

    // (1) Clear state. For "all", also run the global clears so any untracked entry
    //     (e.g. the character-select doll's display-id variants) is wiped too.
    if (all) {
        ColorEngine::ItemTintClear();
        ColorEngine::ItemRetexClear();
    }
    for (int s = lo; s <= hi; ++s) {
        if (g_slotTintFrom[s] > 0) {
            ColorEngine::ItemTintSlotRemove((uint32_t)s);
            g_slotTintFrom[s] = 0;
        }
        if (g_slotRetexFrom[s] > 0) {
            ColorEngine::ItemRetexRemove(g_slotRetexFrom[s]);
            g_slotRetexFrom[s] = 0;
            g_slotRetexTo[s] = 0;
        }
        memset(&g_slotTintApplied[s], 0, sizeof(SlotSkinTint));
        g_skinToItem[s] = 0;
        memset(&g_skinTint[s], 0, sizeof(SlotSkinTint));
        g_skinAppliedTo[s] = 0;
        g_pendingModelTintReload[s] = 0;
    }
    UpdateHasSkin();

    // (2) Model-item textures can be cached under the real path, the donor path, or a
    //     TM_CTINT virtual key. After the maps are cleared, make the client re-decode
    //     every loaded texture once, then also reload the exact affected model textures.
    //     This paints the cached pixels clean (the tint map is empty now). Then arm a
    //     clean identity virtual key for the separate-model slots so the re-attach below
    //     cannot reuse the old tinted CTexture object by cache key.
    ColorEngine::ReloadAllTextures();
    {
        for (int s = lo; s <= hi; ++s) {
            uint32_t ids[5] = { visBefore[s], retFromBefore[s], retToBefore[s], tintFromBefore[s], g_origItems[s] };
            for (int i = 0; i < 5; ++i) {
                uint32_t id = ids[i];
                if (id == 0) continue;
                bool seen = false;
                for (int j = 0; j < i; ++j) {
                    if (ids[j] == id) { seen = true; break; }
                }
                if (!seen) ColorEngine::ReloadModelTexturesForSlot((uint32_t)s, id);
            }
            for (int i = 0; i < 5; ++i) {
                uint32_t id = ids[i];
                if (id == 0) continue;
                bool seen = false;
                for (int j = 0; j < i; ++j) {
                    if (ids[j] == id) { seen = true; break; }
                }
                if (!seen) ColorEngine::ArmCleanModelTexturesForSlot((uint32_t)s, id);
            }
        }
    }

    // (3) ROBUST kill: force a complete detach/re-attach of every visible item using
    //     the originally-equipped items. The object-component attachments (helmet/
    //     shoulder/cape/weapon) cannot drop their cached tinted texture via a plain
    //     refresh, so we MUST destroy and re-create them by writing 0 then the
    //     original item id. The morph system re-stamps morphs on top in step (5).
    ForceFlushOriginalsToVisible(player);

    // (4) Re-equip the model so retex'd items re-attach their original texture, and the
    //     reloaded clean textures are picked up everywhere.
    g_weaponRefreshTicks = 2;
    g_pendingSkinRefreshTicks = 0;     // cancel any coalesced rebuild; we do it here
    g_pendingSkinHardReload = false;
    RefreshPlayerModelFull(player);
    if (CGUnit_UpdateDisplayInfo) {
        ScopedUpdateDisplayInfo(player, 1);
    }
    ForceRefreshComponents(player);

    // (5) Re-stamp any active morph items on top of the freshly-clean originals. The
    //     FlushOriginals step above destroyed every attachment, so we need the morph
    //     descriptors to be written back AND the model to refresh once more for the
    //     morphed items to actually render. The next MorphGuard tick keeps them pinned.
    if (g_hasMorph) {
        ApplyMorphState(player);
        if (CGUnit_UpdateDisplayInfo) {
            ScopedUpdateDisplayInfo(player, 0);
        }
        ForceRefreshComponents(player);
    }

    // (6) Persist cleared state (survives relog; updates the character-select doll).
    SaveFullState(GetPlayerGuid());
}

// Reconcile the LIVE per-slot retex/tint with the persisted skin state
// (g_skinToItem / g_skinTint), binding each skin to the item CURRENTLY VISIBLE in
// its slot (the morphed item if morphed, else the equipped one). This is THE fix for
// "only one skin shows on login / after a loadout": the retex must bind to whatever
// the slot is actually rendering, and that is only correct AFTER the morph items have
// been stamped into the descriptor — which is exactly when MorphGuard / the deferred
// login refresh call this. Idempotent and diff-based: a slot is only touched when its
// binding is stale (visible item changed, or the skin was added/removed), so steady
// frames cost only 19 descriptor reads. NEVER refreshes the model itself — it returns
// whether anything changed and the caller does ONE rebuild (so the bind happens before
// the composite => no flicker). player must be valid.
//
// Side effect: sets s_skinPassWasGearSwap = true if ANY slot's visible item id moved
// in this pass (i.e. the user actually swapped a piece of gear), false otherwise. The
// caller uses this to pick the right refresh: a gear swap means the engine has just
// re-streamed the affected M2, so we only need a lightweight component re-attach to
// push the new tint through the decode hook; a pure tint edit on unchanged items
// needs the body-armor-safe full rebuild to release the cached composite.
bool ApplyPersistedSkins(WowObject* player) {
    if (!player || !player->descriptors) return false;
    uint8_t* desc = (uint8_t*)player->descriptors;
    bool changed = false;
    bool clearedStale = false;
    bool stateDirty = false;
    s_skinPassWasGearSwap = false;

    for (int slot = 1; slot <= 19; ++slot) {
        uint32_t off = GetVisibleItemField(slot);
        uint32_t visId = 0;
        if (off) {
            __try { visId = *(uint32_t*)(desc + off); }
            __except (EXCEPTION_EXECUTE_HANDLER) { visId = 0; }
        }

        // ---- retexture (donor item) ----
        uint32_t donor = g_skinToItem[slot];
        bool hasDesiredSkin = (donor > 0 || g_skinTint[slot].enabled != 0);
        uint32_t sourceId = g_skinAppliedTo[slot];

        if (hasDesiredSkin && sourceId > 0 && visId != sourceId) {
            if (g_slotRetexFrom[slot] > 0) {
                ColorEngine::ItemRetexRemove(g_slotRetexFrom[slot]);
                g_slotRetexFrom[slot] = 0;
                g_slotRetexTo[slot] = 0;
                changed = true;
            }
            if (g_slotTintFrom[slot] > 0) {
                ColorEngine::ItemTintSlotRemove((uint32_t)slot);
                g_slotTintFrom[slot] = 0;
                memset(&g_slotTintApplied[slot], 0, sizeof(SlotSkinTint));
                changed = true;
            }
            g_skinToItem[slot] = 0;
            memset(&g_skinTint[slot], 0, sizeof(SlotSkinTint));
            g_skinAppliedTo[slot] = 0;
            clearedStale = true;
            s_skinPassWasGearSwap = true;
            continue;
        }

        if (hasDesiredSkin && sourceId == 0 && visId > 0) {
            g_skinAppliedTo[slot] = visId;
            stateDirty = true;
        } else if (!hasDesiredSkin) {
            g_skinAppliedTo[slot] = 0;
        }

        bool wantRetex = (donor > 0 && visId > 0 && visId != donor);
        if (wantRetex) {
            if (g_slotRetexFrom[slot] != visId || g_slotRetexTo[slot] != donor) {
                if (g_slotRetexFrom[slot] > 0) ColorEngine::ItemRetexRemove(g_slotRetexFrom[slot]);
                if (ColorEngine::ItemRetexAdd(visId, donor)) {
                    changed = true;
                    if (g_slotRetexFrom[slot] != visId) s_skinPassWasGearSwap = true;
                }
                // Record the source id we (tried to) bind even on failure, so a retex
                // that can't resolve does not retry every frame (no refresh loop).
                g_slotRetexFrom[slot] = visId;
                g_slotRetexTo[slot] = donor;
            }
        } else if (g_slotRetexFrom[slot] > 0) {
            ColorEngine::ItemRetexRemove(g_slotRetexFrom[slot]);
            g_slotRetexFrom[slot] = 0;
            g_slotRetexTo[slot] = 0;
            changed = true;
        }

        // ---- tint (independent of donor: a slot can be tinted with no donor) ----
        const SlotSkinTint& t = g_skinTint[slot];
        bool wantTint = (t.enabled != 0 && visId > 0);
        if (wantTint) {
            bool tintChanged = (memcmp(&g_slotTintApplied[slot], &t, sizeof(SlotSkinTint)) != 0);
            bool visIdChanged = (g_slotTintFrom[slot] != visId);
            if (visIdChanged || tintChanged) {
                if (g_slotTintFrom[slot] > 0) ColorEngine::ItemTintSlotRemove((uint32_t)slot);
                if (ColorEngine::ItemTintSlotSet((uint32_t)slot, visId,
                        (int)t.mode, t.r, t.g, t.b, t.r2, t.g2, t.b2,
                        (int)t.dir, (int)t.mult, (int)t.glowStr, (int)t.contrast,
                        (int)t.span, (int)t.phase,
                        (int)t.brightness, (int)t.saturation, (int)t.hueShift)) {
                    RefreshTintedModelSlot(slot, visId);
                    changed = true;
                }
                g_slotTintFrom[slot] = visId;
                memcpy(&g_slotTintApplied[slot], &t, sizeof(SlotSkinTint));
                if (visIdChanged) s_skinPassWasGearSwap = true;
            }
        } else if (g_slotTintFrom[slot] > 0) {
            ColorEngine::ItemTintSlotRemove((uint32_t)slot);
            g_slotTintFrom[slot] = 0;
            memset(&g_slotTintApplied[slot], 0, sizeof(SlotSkinTint));
            changed = true;
        }
    }
    if (clearedStale || stateDirty) {
        UpdateHasSkin();
        SaveFullState(GetPlayerGuid());
    }
    return changed || clearedStale;
}

    static bool g_justLoggedIn = false;
static int g_loginTicks = 0;

// Soft reset: only clear originals/saved flag but keep morph targets.
// This allows the hook to continue intercepting descriptor writes with the
// correct morph values across zone transitions, preventing mount/morph
// resets that require remount/re-morph to fix.
void SoftResetState(WowObject* player) {
    if (player) {
        uint64_t guid = 0;
        __try {
            uint8_t* desc = (uint8_t*)player->descriptors;
            guid = *(uint64_t*)desc;
        } __except(1) {}
        
        if (guid != 0 && guid != g_lastLoadedGuid) {
            g_lastLoadedGuid = guid;
        }
    } else if (g_lastLoadedGuid != 0) {
        g_lastLoadedGuid = 0;
    }

    g_lastAppliedDisplay = 0;
    g_lastAppliedMount = 0;
    g_suspended = false;

    UpdateHasMorph(); // Recalculate from current morph targets

    // ROBUST LOGIN: Ensure all morph targets are written to descriptors NOW.
    // Do not schedule a delayed refresh here; the state is already visible before
    // it fires, and the late refresh was the 1-second login/reload/teleport blink.
    if ((g_hasMorph || g_hasSkin || g_barberActive) && player && !g_initialRefreshDone) {
        // Enforce character/item/scale state immediately (descriptor writes only).
        bool changed = ApplyMorphState(player);
        // Stamp the saved barber look (skin/face/hair) into PLAYER_BYTES now.
        if (g_barberActive) changed = ApplyBarberToPlayer(player, false) || changed;
        g_initialRefreshDone = true;
        g_pendingInitialRefreshTicks = INITIAL_REFRESH_DELAY_TICKS;
        Log("Login morph descriptors applied; changed=%d skin=%d deferredTicks=%d (MorphId=%u)",
            changed ? 1 : 0, g_hasSkin ? 1 : 0, g_pendingInitialRefreshTicks, g_morphDisplay);
    }

    Log("Soft reset complete");
}

// Kept as a cancellation point for any older path that might arm the deferred
// refresh. New world-entry code keeps it disabled.
void CancelDeferredInitialRefresh() {
    g_pendingInitialRefreshTicks = 0;
    g_initialRefreshDone = true;
}

void ProcessDeferredInitialRefresh(WowObject* player) {
    (void)player;
    if (g_pendingInitialRefreshTicks > 0) {
        g_pendingInitialRefreshTicks = 0;
        Log("Deferred initial refresh suppressed to prevent login/reload blink.");
    }
}

// Fire the coalesced skin/recolor component re-attach once a batch of recolor commands has
// settled (see g_pendingSkinRefreshTicks). Runs every tick from the main loop,
// independently of MorphGuard — so it still fires after a full "Reset All" leaves
// no morph and no skin (g_hasMorph == g_hasSkin == false). No model teardown.
void ProcessDeferredSkinRefresh(WowObject* player) {
    if (g_pendingSkinRefreshTicks <= 0) return;
    if (--g_pendingSkinRefreshTicks > 0) return;
    bool hard = g_pendingSkinHardReload;
    g_pendingSkinHardReload = false;
    if (player && player->descriptors) {
        uint32_t pendingModelReload[20] = {0};
        __try {
            uint8_t* desc = (uint8_t*)player->descriptors;
            for (int slot = 1; slot <= 19; ++slot) {
                uint32_t id = g_pendingModelTintReload[slot];
                g_pendingModelTintReload[slot] = 0;
                if (!id || g_slotTintFrom[slot] != id) continue;
                uint32_t off = GetVisibleItemField(slot);
                uint32_t visId = off ? *(uint32_t*)(desc + off) : 0;
                if (visId == id) pendingModelReload[slot] = id;
            }
        } __except (EXCEPTION_EXECUTE_HANDLER) {}

        for (int slot = 1; slot <= 19; ++slot) {
            if (pendingModelReload[slot]) {
                ColorEngine::ReloadModelTexturesForSlot((uint32_t)slot, pendingModelReload[slot]);
            }
        }

        // Pure item color/retex edits keep the same visible item IDs, so a component
        // re-attach alone can leave the in-world character holding the old baked
        // armor composite until another morph/apply happens. Hard refreshes use the
        // full visible-item bounce to force the live player model to re-compose now.
        if (hard) RefreshPlayerModelFull(player);
        else ForceRefreshComponents(player);
        // Weapons cache their texture/glow independently of the body composite and
        // MorphGuard's own weapon-refresh path is skipped once nothing is morphed
        // (e.g. right after a reset). Re-stamp here so a reskinned/tinted weapon
        // always clears/updates with the batch — no relog.
        ReStampWeapons(player);

        // Keep active character visuals attached across reskins / zone changes.
        if (Visuals_HasActive()) Visuals_Reapply();
    }
}

void ResetAllMorphs(bool forceClearOnly) {
    if (forceClearOnly) {
        g_justLoggedIn = false; // Reset login grace period

        // Just clear internal state so we don't accidentally write old values
        g_morphDisplay = 0; g_morphScale = 0.0f; g_morphMount = 0;
        g_morphPet = 0; g_morphHPet = 0; g_morphHPetScale = 0.0f;
        g_morphEnchantMH = 0; g_morphEnchantOH = 0; g_morphTitle = 0;

        g_origPetDisplay = 0; g_origHPetDisplay = 0;
        g_origEnchantMH = 0; g_origEnchantOH = 0;
        g_origTitle = 0;
        g_origMount = 0; g_origDisplay = 0; g_origScale = 1.0f;

        memset(g_origItems, 0, sizeof(g_origItems));
        memset(g_morphItems, 0, sizeof(g_morphItems));

        // Clear player-clone appearance state (no descriptor to restore here — the
        // player may be null/unloaded on a force-clear; the in-world restore path
        // below handles the descriptor when a player exists).
        g_morphPlayerBytesActive = false; g_origPlayerBytesSaved = false;
        g_morphPlayerBytes = 0; g_morphPlayerFacial = 0;
        g_origPlayerBytes = 0; g_origPlayerFacial = 0;

        g_weaponRefreshTicks = 0;
        g_hasMorph = false;
        g_suspended = false;
        g_saved = false;
        g_initialRefreshDone = false; // allow next character to stamp descriptors once
        g_pendingInitialRefreshTicks = 0; // Cancel any pending deferred refresh from the previous character
        g_pendingSkinRefreshTicks = 0;    // Drop any pending recolor re-bake from the previous character
        g_lastLoadedGuid = 0;        // Reset tracking so we can reload the same character if needed
        g_remoteMorphs.clear();
        ClearSpellMorphs();
        return;
    }

    WowObject* player = GetPlayer();
    if (!player || !player->descriptors) return;
    uint8_t* desc = (uint8_t*)player->descriptors;

    // ALWAYS revert the base model display to native (or the captured original) so a
    // race/creature morph clears on reset even if originals were never captured
    // (g_saved == false). The native display id is always valid, so reset never
    // "sticks" the morphed model anymore.
    {
        uint32_t nativeDisplay = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
        uint32_t restoreDisp = (g_saved && g_origDisplay > 0) ? g_origDisplay : nativeDisplay;
        if (restoreDisp > 0) *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = restoreDisp;
    }

    // Restore player-clone appearance bytes (Copy Target on a real player overwrote
    // our skin/face/hair). Done OUTSIDE the g_saved guard so the original look always
    // comes back on reset, then disarm the clone state.
    if (g_origPlayerBytesSaved) {
        *(uint32_t*)(desc + PLAYER_FIELD_BYTES)  = g_origPlayerBytes;
        *(uint8_t*)(desc + PLAYER_FIELD_BYTES2)  = g_origPlayerFacial;
    }
    g_morphPlayerBytesActive = false; g_origPlayerBytesSaved = false;
    g_morphPlayerBytes = 0; g_morphPlayerFacial = 0;
    g_origPlayerBytes = 0; g_origPlayerFacial = 0;

    if (g_saved) {
        *(float*)(desc + 0x10) = g_origScale;

        for (int s = 1; s <= 19; s++) {
            uint32_t off = GetVisibleItemField(s);
            if (off) *(uint32_t*)(desc + off) = g_origItems[s];
        }
        
        if (g_morphMount > 0) {
            uint32_t curMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
            if (curMount > 0) *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = g_origMount;
        }
        
        if (g_morphTitle > 0) {
            *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = g_origTitle;
        }
        
        if (g_morphEnchantMH > 0) WriteVisibleEnchant(player, 16, g_origEnchantMH);
        if (g_morphEnchantOH > 0) WriteVisibleEnchant(player, 17, g_origEnchantOH);

        // DO NOT clear g_origHPetDisplay here yet.
        // Let MorphGuard see it one last time to restore the actual unit visual.
    }

    // Clear targets
    g_morphDisplay = 0; g_morphScale = 0.0f; g_morphMount = 0;
    g_morphPet = 0; g_morphHPet = 0; g_morphHPetScale = 0.0f;
    g_morphEnchantMH = 0; g_morphEnchantOH = 0; g_morphTitle = 0;
    
    // Note: g_origPetDisplay and g_origHPetDisplay will be cleared by MorphGuard after it restores them.
    // However, if we are clearing originals for a full reset (saved=false), then we clear them here.
    if (!g_saved) {
        g_origPetDisplay = 0; g_origHPetDisplay = 0;
    }
    
    g_origEnchantMH = 0; g_origEnchantOH = 0;
    g_origTitle = 0;
    g_origMount = 0; g_origDisplay = 0; g_origScale = 1.0f;
    
    memset(g_origItems, 0, sizeof(g_origItems));
    memset(g_morphItems, 0, sizeof(g_morphItems));
    
    g_weaponRefreshTicks = 0;
    g_hasMorph = false;
    g_suspended = false;
    g_saved = false;
    ClearSpellMorphs();
    
    // Update visual
    ReapplyActiveBarberTintsForPlayer(player);
    if (CGUnit_UpdateDisplayInfo) {
        ScopedUpdateDisplayInfo(player, 1);
    }
}

static void PushProtectedSpellResultsToLua() {
    if (!FrameScript_Execute) return;
    std::string res = ExportProtectedSpellIds();
    char lCmd[32768];
    sprintf_s(lCmd, sizeof(lCmd), "TRANSMORPHER_PROTECTED_RESULTS = '%s'", res.c_str());
    FrameScript_Execute(lCmd, "Transmorpher", 0);
}

static void PushProtectedSaveResultToLua(bool ok) {
    if (!FrameScript_Execute) return;
    FrameScript_Execute(ok ? "TRANSMORPHER_PROTECTED_SAVE_OK = true" : "TRANSMORPHER_PROTECTED_SAVE_OK = false", "Transmorpher", 0);
}

bool DoMorph(const char* cmd, WowObject* player) {
    if (!player) return false;

    // Handle Remote Morphing (Multiplayer Sync)
    // Format: REMOTE:GUID:SUB_COMMAND
    if (strncmp(cmd, "REMOTE:", 7) == 0) {
        uint64_t remoteGuid = 0;
        const char* guidStr = cmd + 7;
        char* endPtr = nullptr;
        
        // WoW GUIDs are hex strings (sometimes starting with 0x)
        remoteGuid = strtoull(guidStr, &endPtr, 16);
        
        if (remoteGuid != 0 && endPtr && *endPtr == ':') {
            // Find or create remote state
            RemoteMorph& rm = g_remoteMorphs[remoteGuid];
            rm.lastSeen = GetTickCount64();

            const char* s = endPtr + 1;
            if (strncmp(s, "MORPH:", 6) == 0) {
                rm.displayId = (uint32_t)atoi(s + 6);
                Log("Remote GUID %llX: Morph set to %u", remoteGuid, rm.displayId);
            }
            else if (strncmp(s, "SCALE:", 6) == 0) {
                rm.scale = (float)atof(s + 6);
                Log("Remote GUID %llX: Scale set to %.2f", remoteGuid, rm.scale);
            }
            else if (strncmp(s, "ITEM:", 5) == 0) {
                int slot = 0; uint32_t itemId = 0;
                if (sscanf_s(s + 5, "%d:%u", &slot, &itemId) == 2) {
                    if (slot >= 1 && slot <= 19) {
                        rm.items[slot] = itemId;
                        rm.unmorphRelease[slot] = false; // Cancel any pending unmorph
                        Log("Remote GUID %llX: Slot %d set to item %u", remoteGuid, slot, itemId);
                    }
                }
            }
            else if (strncmp(s, "UNMORPH:", 8) == 0) {
                int slot = atoi(s + 8);
                if (slot >= 1 && slot <= 19) {
                    rm.unmorphRelease[slot] = true;
                    Log("Remote GUID %llX: Scheduled release for slot %d", remoteGuid, slot);
                }
            }
            else if (strncmp(s, "ENCHANT_MH:", 11) == 0) rm.enchantMH = (uint32_t)atoi(s + 11);
            else if (strncmp(s, "ENCHANT_OH:", 11) == 0) rm.enchantOH = (uint32_t)atoi(s + 11);
            else if (strncmp(s, "MOUNT:", 6) == 0) {
                int mountIdSigned = atoi(s + 6);
                rm.mountId = (mountIdSigned > 0) ? (uint32_t)mountIdSigned : 0;
            }
            else if (strncmp(s, "PET:", 4) == 0) rm.petId = (uint32_t)atoi(s + 4);
            else if (strncmp(s, "HPET:", 5) == 0) rm.hPetId = (uint32_t)atoi(s + 5);
            else if (strncmp(s, "HPET_SCALE:", 11) == 0) rm.hPetScale = (float)atof(s + 11);
            else if (strncmp(s, "TITLE:", 6) == 0) rm.titleId = (uint32_t)atoi(s + 6);
            else if (strncmp(s, "RESET", 5) == 0) {
                rm.displayId = 0;
                rm.scale = 0.0f;
                rm.enchantMH = 0;
                rm.enchantOH = 0;
                rm.mountId = 0;
                rm.petId = 0;
                rm.hPetId = 0;
                rm.titleId = 0;
                memset(rm.items, 0, sizeof(rm.items));
                memset(rm.unmorphRelease, 0, sizeof(rm.unmorphRelease));
                Log("Remote GUID %llX: Reset requested", remoteGuid);
            }
            
            return false; // Don't trigger local player update
        } else {
            Log("Failed to parse remote GUID from: %s", guidStr);
        }
        return false;
    }

    bool isResetCmd = (strncmp(cmd, "RESET", 5) == 0);
    bool isSilentReset = (strncmp(cmd, "RESET:SILENT", 12) == 0);
    bool shouldPersist = !isSilentReset;

    if (!isResetCmd && !g_hasMorph) {
        SaveOriginals(player);
        RefreshOriginals(player);
    }

    uint8_t* desc = (uint8_t*)player->descriptors;
    bool update = false;

    // REFRESH: commit the current morph state to the descriptors and ask for ONE
    // model rebuild. Sent by the addon at the END of an Apply-All / set batch so the
    // items reliably appear even if every individual ITEM command was a no-op (e.g.
    // the descriptors were reverted by a zone/server update while g_morphItems still
    // matched). Returning true makes the single post-batch CGUnit_UpdateDisplayInfo
    // in dllmain fire exactly once — no per-item refresh burst.
    if (strncmp(cmd, "REFRESH", 7) == 0) {
        if (!g_suspended) ApplyMorphState(player);   // re-stamp display + items + scale
        return true;                                  // -> one batch rebuild
    }

    // Morph into another unit's current display (e.g. "Morph into Target").
    // The addon passes the unit GUID (hex); we read its display ID and reuse the
    // normal MORPH path. Reuses GetObjectPtr + UNIT_FIELD_DISPLAYID like the pet
    // guards, so it is as safe as the existing morph code.
    if (strncmp(cmd, "MORPH_GUID:", 11) == 0) {
        uint64_t targetGuid = strtoull(cmd + 11, nullptr, 16);
        // Optional trailing ":1" / ":0" tells us whether the target is a real
        // PLAYER. strtoull stops at the ':' so the guid still parses cleanly.
        // Why this matters: a creature/NPC display id already encodes its WHOLE
        // look (body + baked gear via CDIExtra). The player's own equipped items
        // are still stamped in the visible-item descriptor fields, so doing a
        // bare MORPH left those fields intact and WoW tried to render the NPC body
        // wearing YOUR gear -> "two races merged + half-naked". For an exact NPC
        // clone we therefore HIDE the player's own visible items. For a real
        // player target we instead COPY their visible transmog so they match.
        bool targetIsPlayer = false;
        const char* flag = strchr(cmd + 11, ':');
        if (flag && (flag[1] == '1' || flag[1] == 'p' || flag[1] == 'P')) targetIsPlayer = true;
        if (targetGuid != 0) {
            WowObject* targetObj = GetObjectPtr(targetGuid, TYPEMASK_UNIT, __FILE__, __LINE__);
            if (targetObj && targetObj->descriptors) {
                uint8_t* tdesc = (uint8_t*)targetObj->descriptors;
                uint32_t targetDisp = *(uint32_t*)(tdesc + UNIT_FIELD_DISPLAYID);
                if (targetDisp > 0 && targetDisp != 621) {
                    char sub[32];
                    sprintf_s(sub, sizeof(sub), "MORPH:%u", targetDisp);
                    Log("Morph into unit %llX -> display %u (player=%d)", targetGuid, targetDisp, targetIsPlayer ? 1 : 0);
                    DoMorph(sub, player);
                    // PLAYER CLONE: a player's skin/face/hair come from PLAYER_BYTES,
                    // NOT the display id. Without copying these the stolen race body
                    // renders with OUR customization (e.g. blood-elf body + orc skin).
                    // Copy the target's appearance bytes and arm MorphGuard to keep
                    // them stamped (the engine rebuilds these fields on refresh).
                    if (targetIsPlayer && player && player->descriptors) {
                        uint8_t* ldesc = (uint8_t*)player->descriptors;
                        if (!g_origPlayerBytesSaved) {
                            g_origPlayerBytes  = *(uint32_t*)(ldesc + PLAYER_FIELD_BYTES);
                            g_origPlayerFacial = *(uint8_t*)(ldesc + PLAYER_FIELD_BYTES2);
                            g_origPlayerBytesSaved = true;
                        }
                        g_morphPlayerBytes  = *(uint32_t*)(tdesc + PLAYER_FIELD_BYTES);
                        g_morphPlayerFacial = *(uint8_t*)(tdesc + PLAYER_FIELD_BYTES2);
                        g_morphPlayerBytesActive = true;
                        *(uint32_t*)(ldesc + PLAYER_FIELD_BYTES)  = g_morphPlayerBytes;
                        *(uint8_t*)(ldesc + PLAYER_FIELD_BYTES2)  = g_morphPlayerFacial;
                    }
                    // Snapshot the target's gear (player) or clear ours (NPC) so the
                    // copy is exact, then commit ONE rebuild via REFRESH.
                    for (int s = 1; s <= 19; s++) {
                        uint32_t toff = GetVisibleItemField(s);
                        if (!toff) continue;
                        char itemCmd[48];
                        if (targetIsPlayer) {
                            uint32_t titem = *(uint32_t*)(tdesc + toff);
                            sprintf_s(itemCmd, sizeof(itemCmd), "ITEM:%d:%u", s, titem); // 0 -> hidden
                        } else {
                            sprintf_s(itemCmd, sizeof(itemCmd), "ITEM:%d:0", s);          // hide our gear
                        }
                        DoMorph(itemCmd, player);
                    }
                    // Tell the addon which display we resolved so Copy Target behaves
                    // like every other morph: it lands in the canonical state and shows
                    // in the panel (the addon can't read a unit's display id itself, so
                    // the DLL reports it here). The addon owns the state update.
                    if (FrameScript_Execute) {
                        char notify[96];
                        sprintf_s(notify, sizeof(notify),
                            "if TransmorpherAdoptMorph then TransmorpherAdoptMorph(%u) end", targetDisp);
                        __try { FrameScript_Execute(notify, "Transmorpher", 0); } __except(1) {}
                    }
                    return DoMorph("REFRESH", player);
                }
            }
        }
        return false;
    }

    // Forces the player's model/equipment to fully re-bake so a texture recolor
    // shows immediately, exactly like an equipment morph — no unequip/re-equip.
    // A texture swap keeps the same item IDs, so a plain UpdateDisplayInfo may
    // skip the re-bake; the display "double-update" (write 621 then restore) the
    // morph code already uses guarantees a full model + armor-texture rebuild.
    // Full, body-armor-safe appearance rebuild (shared with MorphGuard / login). See
    // RefreshPlayerModelFull for why the visible-item bounce is required.
    //
    // Recolor commands DON'T rebuild inline — they arm the coalesced counter so a
    // whole batch (e.g. "Color All" = up to 19 commands in one frame) produces ONE
    // rebuild after it settles. This is what makes apply AND remove flicker-free and
    // relog-free (the old per-command re-bake flickered and raced the compositor's
    // texture release, which is why a removal "sometimes" stuck until relog).
    auto RefreshPlayerAppearance = [&]() { g_pendingSkinRefreshTicks = SKIN_REFRESH_DELAY_TICKS; };

    // ---- ColorEngine commands (texture swap, fog color, particle tint) ----
    if (strncmp(cmd, "TEXSWAP_CLEAR", 13) == 0) { ColorEngine::TexSwapClear(); return false; }
    if (strncmp(cmd, "TEXSWAP_DEL:", 12) == 0) { ColorEngine::TexSwapRemove(cmd + 12); return false; }
    if (strncmp(cmd, "TEXSWAP:", 8) == 0) {
        const char* s = cmd + 8;
        const char* bar = strchr(s, '|');
        if (bar) {
            char fromBuf[300];
            size_t n = (size_t)(bar - s);
            if (n > 0 && n < sizeof(fromBuf)) {
                memcpy(fromBuf, s, n);
                fromBuf[n] = '\0';
                ColorEngine::TexSwapAdd(fromBuf, bar + 1);
            }
        }
        return false;
    }
    // Weapon sheath position. SHEATHE:<slot>:<value>  slot 0=mainhand,1=offhand;
    // value -1=natural, 1=back, 3=hip, 7=hidden. SHEATHE_OFF clears both.
    if (strncmp(cmd, "SHEATHE_OFF", 11) == 0) {
        SetSheatheOverride(0, -1); SetSheatheOverride(1, -1); RefreshSheathe();
        SaveFullState(GetPlayerGuid()); return false;
    }
    if (strncmp(cmd, "SHEATHE:", 8) == 0) {
        int slot = 0, value = -1; sscanf_s(cmd + 8, "%d:%d", &slot, &value);
        SetSheatheOverride(slot, value); RefreshSheathe();
        SaveFullState(GetPlayerGuid()); return false;
    }
    if (strncmp(cmd, "FOGCOLOR_OFF", 12) == 0) { ColorEngine::SetFogColor(false, 0, 0, 0, 0.0f, 0.0f); return false; }
    if (strncmp(cmd, "FOGCOLOR:", 9) == 0) {
        int r = 0, g = 0, b = 0; float st = 0.1f, en = 1.0f;
        sscanf_s(cmd + 9, "%d:%d:%d:%f:%f", &r, &g, &b, &st, &en);
        ColorEngine::SetFogColor(true, (uint8_t)r, (uint8_t)g, (uint8_t)b, st, en);
        return false;
    }
    if (strncmp(cmd, "DIAGTEX:", 8) == 0) { ColorEngine::SetTexDiag(atoi(cmd + 8) != 0); return false; }

    // ---- BARBER: customize the player's OWN base model -------------------------
    // BARBER:skin:face:hairStyle:hairColor:facialHair  -> set + rebuild + persist.
    // Each value is a 0..255 customization index (the same indices the in-game
    // barbershop uses; invalid values fall back to the nearest geoset). Sending
    // BARBER re-stamps PLAYER_BYTES and rebuilds the model so it shows at once.
    if (strncmp(cmd, "BARBER_GET", 10) == 0) {
        // Publish the player's CURRENT appearance bytes to the addon so the Barber
        // tab can initialise its steppers from the real values. Reads the live
        // descriptor (or the captured original / active barber if set).
        int cmdRace = 0, cmdSex = 0;
        sscanf_s(cmd + 10, ":%d:%d", &cmdRace, &cmdSex);
        EffectiveBarberLook look;
        uint32_t bytes = 0; uint8_t facial = 0;
        if (ResolveEffectiveBarberLook(player, cmdRace, cmdSex, &look)) {
            bytes = (uint32_t)(look.skin & 0xFF)
                  | ((uint32_t)(look.face & 0xFF) << 8)
                  | ((uint32_t)(look.hair & 0xFF) << 16)
                  | ((uint32_t)(look.hairColor & 0xFF) << 24);
            facial = (uint8_t)(look.facial & 0xFF);
        } else if (g_barberActive) {
            bytes = BarberPackBytes(); facial = g_barberFacial;
        } else if (player && player->descriptors) {
            uint8_t* d = (uint8_t*)player->descriptors;
            __try { bytes = *(uint32_t*)(d + PLAYER_FIELD_BYTES); facial = *(uint8_t*)(d + PLAYER_FIELD_BYTES2); }
            __except (EXCEPTION_EXECUTE_HANDLER) {}
        }
        if (FrameScript_Execute) {
            char buf[160];
            sprintf_s(buf, sizeof(buf),
                "if TransmorpherBarberReport then TransmorpherBarberReport(%u,%u,%u,%u,%u,%u) end",
                bytes & 0xFF, (bytes >> 8) & 0xFF, (bytes >> 16) & 0xFF, (bytes >> 24) & 0xFF,
                (uint32_t)facial, g_barberActive ? 1u : 0u);
            __try { FrameScript_Execute(buf, "Transmorpher", 0); } __except (1) {}
        }
        // Publish the REAL per-race/gender option counts from the char DBCs so the
        // Barber tab's sliders span the true range (not a flat guess). Prefer the
        // visible display id's resolved character race/sex so a morphed Human uses
        // Human barber options even when the native player is Blood Elf, etc.
        if (FrameScript_Execute) {
            int race = look.race, sex = look.sex, classId = look.classId;
            if (race > 0) {
                int mSkin = 0, mFace = 0, mHair = 0, mHairColor = 0, mFacial = 0;
                ColorEngine::GetBarberMaxes(race, sex, &mSkin, &mFace, &mHair, &mHairColor, &mFacial);
                char mbuf[192];
                sprintf_s(mbuf, sizeof(mbuf),
                    "if TransmorpherBarberMaxes then TransmorpherBarberMaxes(%d,%d,%d,%d,%d) end",
                    mSkin, mFace, mHair, mHairColor, mFacial);
                __try { FrameScript_Execute(mbuf, "Transmorpher", 0); } __except (1) {}

                char vSkin[256] = {0}, vFace[256] = {0}, vHair[256] = {0}, vHairColor[256] = {0}, vFacial[256] = {0};
                ColorEngine::GetBarberValueLists(race, sex, classId,
                    (int)(bytes & 0xFF), (int)((bytes >> 8) & 0xFF),
                    (int)((bytes >> 16) & 0xFF), (int)((bytes >> 24) & 0xFF), (int)facial,
                    vSkin, sizeof(vSkin), vFace, sizeof(vFace), vHair, sizeof(vHair),
                    vHairColor, sizeof(vHairColor), vFacial, sizeof(vFacial));
                char vbuf[1400];
                sprintf_s(vbuf, sizeof(vbuf),
                    "if TransmorpherBarberValues then TransmorpherBarberValues('%s','%s','%s','%s','%s') end",
                    vSkin, vFace, vHair, vHairColor, vFacial);
                __try { FrameScript_Execute(vbuf, "Transmorpher", 0); } __except (1) {}
            }
        }
        return false;
    }
    if (strncmp(cmd, "BARBER_OFF", 10) == 0) {
        if (g_barberActive && g_barberOrigSaved && player && player->descriptors) {
            uint8_t* d = (uint8_t*)player->descriptors;
            __try {
                *(uint32_t*)(d + PLAYER_FIELD_BYTES)  = g_barberOrigBytes;
                *(uint8_t*)(d + PLAYER_FIELD_BYTES2)  = g_barberOrigFacial;
            } __except (EXCEPTION_EXECUTE_HANDLER) {}
        }
        g_barberActive = false;
        g_barberOrigSaved = false;
        if (player) RefreshPlayerModelFull(player);
        SaveFullState(GetPlayerGuid());
        return false;
    }
    if (strncmp(cmd, "BARBER:", 7) == 0) {
        int sk = 0, fc = 0, hr = 0, hc = 0, fh = 0;
        if (sscanf_s(cmd + 7, "%d:%d:%d:%d:%d", &sk, &fc, &hr, &hc, &fh) >= 1) {
            // Capture the real look BEFORE the first stamp so Reset restores it.
            if (!g_barberActive) CaptureBarberOriginal(player);
            g_barberSkin      = (uint8_t)(sk & 0xFF);
            g_barberFace      = (uint8_t)(fc & 0xFF);
            g_barberHair      = (uint8_t)(hr & 0xFF);
            g_barberHairColor = (uint8_t)(hc & 0xFF);
            g_barberFacial    = (uint8_t)(fh & 0xFF);
            g_barberActive    = true;
            ApplyBarberToPlayer(player, true);
            SaveFullState(GetPlayerGuid());
        }
        return false;
    }
    // Free-RGB BLP recolor of a body/hair region. The DLL reads the player's actual
    // texture filenames from CharSections and tints them with the full effect set.
    //   BARBER_TINT_CLEAR              -> drop all region tints
    //   BARBER_TINT_OFF:region         -> drop one region's tint
    //   BARBER_TINT:region:race:sex:skin:face:hair:haircolor:facial:mode:r:g:b:
    //               r2:g2:b2:dir:mult:glow:contrast:span:phase:bright:sat:hue
    if (strncmp(cmd, "BARBER_TINT_CLEAR", 17) == 0) {
        ColorEngine::ClearBarberRegionTints();
        ClearBarberTintMirror();
        SaveBarberTintFile(GetPlayerGuid());   // empty mirror -> deletes the sidecar
        // Repaint cached pixels clean: the skin/face BLPs were already decoded+composited
        // WITH the tint, so a plain refresh reuses that baked texture and the recolor (incl.
        // glowing eyes) "sticks" after reset. ReloadAllTextures re-decodes every loaded
        // texture now that the tint maps are empty, then a hard re-stream re-composites the
        // body from the clean BLPs. Same proven path the Skin-tab clean reset uses.
        ColorEngine::ReloadAllTextures();
        if (player) RefreshPlayerModelFull(player);
        return false;
    }
    if (strncmp(cmd, "BARBER_TINT_OFF:", 16) == 0) {
        int region = atoi(cmd + 16);
        ColorEngine::SetBarberRegionTint(region, 0, 0, 0, 0, 0, 0, 0, 0, false,
                                         0, 0, 0, 0, 0, 0, 0, 0, 100, 0, 100, 100, 0, 128, 0, 0);
        SetBarberTintRegion(region, nullptr);
        SaveBarberTintFile(GetPlayerGuid());
        ColorEngine::ReloadAllTextures();      // re-decode the cleared region's BLP clean
        if (player) RefreshPlayerModelFull(player);
        return false;
    }
    if (strncmp(cmd, "BARBER_TINT:", 12) == 0) {
        int region = 0, race = 0, sex = 0, skin = 0, face = 0, hair = 0, haircolor = 0, facial = 0;
        int mode = 0, r = 255, g = 80, b = 80, r2 = 60, g2 = 120, b2 = 255, dir = 0, mult = 130;
        int glow = 0, contrast = 100, span = 100, phase = 0, bright = 128, sat = 0, hue = 0;
        int n = sscanf_s(cmd + 12,
            "%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d",
            &region, &race, &sex, &skin, &face, &hair, &haircolor, &facial,
            &mode, &r, &g, &b, &r2, &g2, &b2, &dir, &mult, &glow, &contrast, &span, &phase,
            &bright, &sat, &hue);
        if (n >= 9) {
            int classId = 0;
            // The visible character texture is selected by the visible display's
            // character race/sex plus the active appearance bytes. Prefer that over
            // Lua's native UnitRace/UnitSex so barber color follows race morphs.
            EffectiveBarberLook look;
            if (ResolveEffectiveBarberLook(player, race, sex, &look)) {
                race = look.race;
                sex = look.sex;
                classId = look.classId;
                skin = look.skin;
                face = look.face;
                hair = look.hair;
                haircolor = look.hairColor;
                facial = look.facial;
            }
            ColorEngine::SetBarberRegionTint(region, race, sex, classId, skin, face, hair, haircolor, facial,
                true, mode,
                (uint8_t)r, (uint8_t)g, (uint8_t)b, (uint8_t)r2, (uint8_t)g2, (uint8_t)b2,
                dir, mult, glow, contrast, span, phase, bright, sat, hue);
            // Mirror + persist the region's params so the COLORS replay on the cold-start
            // character-select doll (the addon can't push them at the glue screen).
            if (region >= 0 && region <= 3) {
                SlotSkinTint rec = {};
                rec.enabled = 1; rec.mode = (uint32_t)mode;
                rec.r = (uint8_t)r; rec.g = (uint8_t)g; rec.b = (uint8_t)b;
                rec.r2 = (uint8_t)r2; rec.g2 = (uint8_t)g2; rec.b2 = (uint8_t)b2;
                rec.dir = (uint32_t)dir; rec.mult = (uint32_t)mult; rec.glowStr = (uint32_t)glow;
                rec.contrast = (uint32_t)contrast; rec.span = (uint32_t)span; rec.phase = (uint32_t)phase;
                rec.brightness = (uint32_t)bright; rec.saturation = sat; rec.hueShift = (uint32_t)hue;
                SetBarberTintRegion(region, &rec);
                SaveBarberTintFile(GetPlayerGuid());
            }
            if (player) RefreshPlayerModelFull(player);
        }
        return false;
    }
    // Reset All — one synchronous, self-contained clean reset of every slot, fired now.
    if (strncmp(cmd, "ITEM_RETEX_CLEAR", 16) == 0) {
        Log("[RESET] ITEM_RETEX_CLEAR received -> CleanResetSlots(all) player=%p", player);
        CleanResetSlots(player, 0);
        Log("[RESET] ITEM_RETEX_CLEAR done");
        return false;
    }
    // Manual per-item reset — same synchronous clean reset, one slot. ITEM_SKIN_RESET:idx
    if (strncmp(cmd, "ITEM_SKIN_RESET:", 16) == 0) {
        int slot = atoi(cmd + 16);
        Log("[RESET] ITEM_SKIN_RESET:%d received player=%p", slot, player);
        if (slot >= 1 && slot <= 19) CleanResetSlots(player, slot);
        Log("[RESET] ITEM_SKIN_RESET:%d done", slot);
        return false;
    }
    if (strncmp(cmd, "ITEM_RETEX_DEL:", 15) == 0) { ColorEngine::ItemRetexRemove((uint32_t)atoi(cmd + 15)); g_pendingSkinHardReload = true; RefreshPlayerAppearance(); return false; }
    if (strncmp(cmd, "ITEM_RETEX:", 11) == 0) {
        int fromId = 0, toId = 0;
        if (sscanf_s(cmd + 11, "%d:%d", &fromId, &toId) == 2 && fromId > 0 && toId > 0) {
            if (ColorEngine::ItemRetexAdd((uint32_t)fromId, (uint32_t)toId)) {
                g_pendingSkinHardReload = true;
                RefreshPlayerAppearance();
            }
        }
        return false;
    }
    // Slot-based retexture. Unlike ITEM_RETEX (which takes the base item id the
    // addon read with GetInventoryItemID), this reads the item that is ACTUALLY
    // rendered in the slot straight from the visible-item descriptor field. That
    // is the only id that works when a SERVER-SIDE transmog (e.g. Warmane) is
    // active and unmorphed: the worn item differs from the displayed one, so
    // retexturing the base item changed nothing. Reading the visible field gives
    // us the displayed item, so the skin lands on what the player sees.
    if (strncmp(cmd, "ITEM_RETEX_SLOT_DEL:", 20) == 0) {
        int slot = atoi(cmd + 20);
        if (slot >= 1 && slot <= 19) {
            bool removed = false;
            if (g_slotTintFrom[slot] > 0) {
                ColorEngine::ItemTintSlotRemove((uint32_t)slot);
                g_slotTintFrom[slot] = 0;
                memset(&g_slotTintApplied[slot], 0, sizeof(SlotSkinTint));
                removed = true;
            }
            // Remove the exact source id we applied (tracked per slot), so the
            // retex is cleaned up correctly even if the worn item changed since.
            if (g_slotRetexFrom[slot] > 0) {
                ColorEngine::ItemRetexRemove(g_slotRetexFrom[slot]);
                g_slotRetexFrom[slot] = 0;
                g_slotRetexTo[slot] = 0;
                removed = true;
            }
            // Refresh on ANY removal (the old code only refreshed when a retex was
            // present, so clearing a tint-only object slot left it colored). Mark a
            // hard reload so helmet/shoulder/weapon attachments re-resolve clean.
            if (removed) { g_pendingSkinHardReload = true; RefreshPlayerAppearance(); }
        }
        return false;
    }
    if (strncmp(cmd, "ITEM_RETEX_SLOT:", 16) == 0) {
        int slot = 0, toId = 0;
        if (sscanf_s(cmd + 16, "%d:%d", &slot, &toId) == 2 &&
            slot >= 1 && slot <= 19 && toId > 0 && player && player->descriptors) {
            uint32_t off = GetVisibleItemField(slot);
            if (off) {
                uint32_t visId = *(uint32_t*)((uint8_t*)player->descriptors + off);
                if (g_slotTintFrom[slot] > 0) {
                    ColorEngine::ItemTintSlotRemove((uint32_t)slot);
                    g_slotTintFrom[slot] = 0;
                    memset(&g_slotTintApplied[slot], 0, sizeof(SlotSkinTint));
                }
                // Drop any previous retex on this slot before applying the new one.
                if (g_slotRetexFrom[slot] > 0 && g_slotRetexFrom[slot] != visId) {
                    ColorEngine::ItemRetexRemove(g_slotRetexFrom[slot]);
                    g_slotRetexFrom[slot] = 0;
                    g_slotRetexTo[slot] = 0;
                }
                if (visId > 0 && visId != (uint32_t)toId) {
                    if (ColorEngine::ItemRetexAdd(visId, (uint32_t)toId)) {
                        g_slotRetexFrom[slot] = visId;
                        g_slotRetexTo[slot] = (uint32_t)toId;
                        g_skinAppliedTo[slot] = visId;
                        g_pendingSkinHardReload = true;
                        RefreshPlayerAppearance();
                    }
                }
            }
        }
        return false;
    }
    if (strncmp(cmd, "ITEM_TINT_CLEAR", 15) == 0) {
        ColorEngine::ItemTintClear(); memset(g_slotTintFrom, 0, sizeof(g_slotTintFrom));
        memset(g_slotTintApplied, 0, sizeof(g_slotTintApplied));
        g_weaponRefreshTicks = 2;
        g_pendingSkinHardReload = true;
        RefreshPlayerAppearance(); return false;
    }
    if (strncmp(cmd, "ITEM_TINT_SLOT_DEL:", 19) == 0) {
        int slot = atoi(cmd + 19);
        if (slot >= 1 && slot <= 19) {
            ColorEngine::ItemTintSlotRemove((uint32_t)slot);
            g_slotTintFrom[slot] = 0;
            memset(&g_slotTintApplied[slot], 0, sizeof(SlotSkinTint));
            if (slot >= 16 && slot <= 18) g_weaponRefreshTicks = 2;
            g_pendingSkinHardReload = true;
            RefreshPlayerAppearance();
        }
        return false;
    }
    // Extended tint (Customize popup): full effect set.
    //   ITEM_TINTX_SLOT:slot:mode:r:g:b:r2:g2:b2:dir:mult:glowStr:contrast:rainbowSpan:phase:brightness:saturation:hueShift
    if (strncmp(cmd, "ITEM_TINTX_SLOT:", 16) == 0) {
        int slot=0, mode=0, r=255,g=255,b=255, r2=0,g2=0,b2=0, dir=0, mult=130, glowStr=0, contrast=100, span=100, phase=0;
        int brightness=128, saturation=0, hueShift=0;
        // >=12 reads the original 14-field message (everything except the v5 post-effects).
        // >=15 reads the full v5 message. Older Lua clients still get a working tint; the
        // post-effects silently default to neutral on the C++ side.
        int nRead = sscanf_s(cmd + 16, "%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d",
                     &slot,&mode,&r,&g,&b,&r2,&g2,&b2,&dir,&mult,&glowStr,&contrast,&span,&phase,
                     &brightness,&saturation,&hueShift);
        if ((nRead == 14 || nRead == 17) &&
            slot >= 1 && slot <= 19 && player && player->descriptors) {
            uint32_t off = GetVisibleItemField(slot);
            if (off) {
                uint32_t visId = *(uint32_t*)((uint8_t*)player->descriptors + off);
                if (visId > 0 && ColorEngine::ItemTintSlotSet((uint32_t)slot, visId,
                        mode, (uint8_t)r,(uint8_t)g,(uint8_t)b, (uint8_t)r2,(uint8_t)g2,(uint8_t)b2,
                        dir, mult, glowStr, contrast, span, phase,
                        brightness, saturation, hueShift)) {
                    RefreshTintedModelSlot(slot, visId);
                    g_slotTintFrom[slot] = visId;
                    g_skinAppliedTo[slot] = visId;
                    memset(&g_slotTintApplied[slot], 0, sizeof(SlotSkinTint));
                    g_slotTintApplied[slot].enabled = 1;
                    g_slotTintApplied[slot].mode = (uint32_t)mode;
                    g_slotTintApplied[slot].r = (uint8_t)r;
                    g_slotTintApplied[slot].g = (uint8_t)g;
                    g_slotTintApplied[slot].b = (uint8_t)b;
                    g_slotTintApplied[slot].r2 = (uint8_t)r2;
                    g_slotTintApplied[slot].g2 = (uint8_t)g2;
                    g_slotTintApplied[slot].b2 = (uint8_t)b2;
                    g_slotTintApplied[slot].dir = (uint32_t)dir;
                    g_slotTintApplied[slot].mult = (uint32_t)mult;
                    g_slotTintApplied[slot].glowStr = (uint32_t)glowStr;
                    g_slotTintApplied[slot].contrast = (uint32_t)contrast;
                    g_slotTintApplied[slot].span = (uint32_t)span;
                    g_slotTintApplied[slot].phase = (uint32_t)phase;
                    g_slotTintApplied[slot].brightness = (uint32_t)brightness;
                    g_slotTintApplied[slot].saturation = (int32_t)saturation;
                    g_slotTintApplied[slot].hueShift = (uint32_t)hueShift;
                    // Mirror the new values into g_skinTint too. The reconciler reads
                    // g_skinTint and re-applies on mismatch with g_slotTintApplied;
                    // without this mirror, every slider change briefly applies then the
                    // next reconciler pass rewinds the phase (and every other field) to
                    // the previous g_skinTint values. PERSIST is sent right after from
                    // Lua and would update g_skinTint eventually, but the reconciler can
                    // race in between and revert the user's drag. Mirroring here makes
                    // the C++ state self-consistent regardless of the Send order.
                    g_skinTint[slot].enabled  = 1;
                    g_skinTint[slot].mode     = (uint32_t)mode;
                    g_skinTint[slot].r        = (uint8_t)r;
                    g_skinTint[slot].g        = (uint8_t)g;
                    g_skinTint[slot].b        = (uint8_t)b;
                    g_skinTint[slot].r2       = (uint8_t)r2;
                    g_skinTint[slot].g2       = (uint8_t)g2;
                    g_skinTint[slot].b2       = (uint8_t)b2;
                    g_skinTint[slot].dir      = (uint32_t)dir;
                    g_skinTint[slot].mult     = (uint32_t)mult;
                    g_skinTint[slot].glowStr  = (uint32_t)glowStr;
                    g_skinTint[slot].contrast = (uint32_t)contrast;
                    g_skinTint[slot].span     = (uint32_t)span;
                    g_skinTint[slot].phase    = (uint32_t)phase;
                    g_skinTint[slot].brightness = (uint32_t)brightness;
                    g_skinTint[slot].saturation = (int32_t)saturation;
                    g_skinTint[slot].hueShift   = (uint32_t)hueShift;
                    if (slot >= 16 && slot <= 18) g_weaponRefreshTicks = 2;
                    g_pendingSkinHardReload = true;
                    RefreshPlayerAppearance();
                }
            }
        }
        return false;
    }
    if (strncmp(cmd, "ITEM_TINT_SLOT:", 15) == 0) {
        int slot = 0, r = 255, g = 255, b = 255, mult = 100, rainbow = 0, glow = 0;
        if (sscanf_s(cmd + 15, "%d:%d:%d:%d:%d:%d:%d", &slot, &r, &g, &b, &mult, &rainbow, &glow) == 7 &&
            slot >= 1 && slot <= 19 && player && player->descriptors) {
            uint32_t off = GetVisibleItemField(slot);
            if (off) {
                uint32_t visId = *(uint32_t*)((uint8_t*)player->descriptors + off);
                if (visId > 0 && ColorEngine::ItemTintSlotSet((uint32_t)slot, visId,
                        rainbow != 0 ? 2 : 0, (uint8_t)r, (uint8_t)g, (uint8_t)b, 0,0,0,
                        0, mult, glow != 0 ? 60 : 0, 100, 100, 0,
                        128, 0, 0)) {
                    RefreshTintedModelSlot(slot, visId);
                    g_slotTintFrom[slot] = visId;
                    g_skinAppliedTo[slot] = visId;
                    memset(&g_slotTintApplied[slot], 0, sizeof(SlotSkinTint));
                    g_slotTintApplied[slot].enabled = 1;
                    g_slotTintApplied[slot].mode = (uint32_t)(rainbow != 0 ? 2 : 0);
                    g_slotTintApplied[slot].r = (uint8_t)r;
                    g_slotTintApplied[slot].g = (uint8_t)g;
                    g_slotTintApplied[slot].b = (uint8_t)b;
                    g_slotTintApplied[slot].dir = 0;
                    g_slotTintApplied[slot].mult = (uint32_t)mult;
                    g_slotTintApplied[slot].glowStr = (uint32_t)(glow != 0 ? 60 : 0);
                    g_slotTintApplied[slot].contrast = 100;
                    g_slotTintApplied[slot].span = 100;
                    g_slotTintApplied[slot].phase = 0;
                    g_slotTintApplied[slot].brightness = 128;
                    g_slotTintApplied[slot].saturation = 0;
                    g_slotTintApplied[slot].hueShift = 0;
                    g_skinTint[slot].enabled  = 1;
                    g_skinTint[slot].mode     = (uint32_t)(rainbow != 0 ? 2 : 0);
                    g_skinTint[slot].r        = (uint8_t)r;
                    g_skinTint[slot].g        = (uint8_t)g;
                    g_skinTint[slot].b        = (uint8_t)b;
                    g_skinTint[slot].dir      = 0;
                    g_skinTint[slot].mult     = (uint32_t)mult;
                    g_skinTint[slot].glowStr  = (uint32_t)(glow != 0 ? 60 : 0);
                    g_skinTint[slot].contrast = 100;
                    g_skinTint[slot].span     = 100;
                    g_skinTint[slot].phase    = 0;
                    g_skinTint[slot].brightness = 128;
                    g_skinTint[slot].saturation = 0;
                    g_skinTint[slot].hueShift   = 0;
                    if (slot >= 16 && slot <= 18) g_weaponRefreshTicks = 2;
                    g_pendingSkinHardReload = true;
                    RefreshPlayerAppearance();
                }
            }
        }
        return false;
    }
    // PERSIST: store the active skin (donor item id) + tint for one slot in the
    // C++ in-memory cache AND flush to the per-character state file. Format:
    //   ITEM_SKIN_PERSIST:slot:toItemId:enabled:mode:r:g:b:r2:g2:b2:dir:mult:glowStr:contrast:span:phase:brightness:saturation:hueShift:appliedToItemId
    // toItemId=0 + enabled=0 means "clear the skin for this slot"; toItemId=0
    // + enabled=1 means tint-only, so coloring works without a donor skin.
    // appliedToItemId anchors the skin to the item it was created on; if the slot
    // later renders a different item, the reconciler clears the skin instead of
    // transferring the color to that new item. appliedToItemId=-1 is used by Lua's
    // login/bulk mirror path to defer binding until MorphGuard has stamped saved
    // morph/loadout descriptors, avoiding an early bind to base equipped gear.
    if (strncmp(cmd, "ITEM_SKIN_PERSIST:", 18) == 0) {
        int slot = 0, toId = 0, enabled = 0, mode = 0;
        int r = 255, g = 80, b = 80, r2 = 60, g2 = 120, b2 = 255;
        int dir = 0, mult = 130, glowStr = 0, contrast = 100, span = 100, phase = 0;
        int brightness = 128, saturation = 0, hueShift = 0, appliedTo = 0;
        int nRead = sscanf_s(cmd + 18, "%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d",
                     &slot, &toId, &enabled, &mode,
                     &r, &g, &b, &r2, &g2, &b2,
                     &dir, &mult, &glowStr, &contrast, &span, &phase,
                     &brightness, &saturation, &hueShift, &appliedTo);
        // Accept v4 (16 fields), v5 (19 fields), the old 18-field Lua typo, and
        // v6 (20 fields with the item this skin is anchored to).
        if (nRead >= 16 && slot >= 1 && slot <= 19) {
            if (nRead < 17) brightness = 128;
            if (nRead < 18) saturation = 0;
            if (nRead < 19) hueShift = 0;
            if (nRead < 20) appliedTo = 0;
            bool deferBind = (nRead >= 20 && appliedTo < 0);
            if (deferBind) appliedTo = 0;
            if (toId == 0 && !enabled) {
                g_skinToItem[slot] = 0;
                memset(&g_skinTint[slot], 0, sizeof(SlotSkinTint));
                g_skinAppliedTo[slot] = 0;
                // Drop any LIVE binding for this slot right now. This makes a per-slot
                // clear self-sufficient even when nothing else (morph/other skin) is
                // left to drive the MorphGuard reconcile. Without this the old retex/
                // tint could linger until a relog.
                bool removed = false;
                if (g_slotTintFrom[slot] > 0) {
                    ColorEngine::ItemTintSlotRemove((uint32_t)slot);
                    g_slotTintFrom[slot] = 0; removed = true;
                    memset(&g_slotTintApplied[slot], 0, sizeof(SlotSkinTint));
                }
                if (g_slotRetexFrom[slot] > 0) {
                    ColorEngine::ItemRetexRemove(g_slotRetexFrom[slot]);
                    g_slotRetexFrom[slot] = 0; removed = true;
                    g_slotRetexTo[slot] = 0;
                }
                if (removed) { g_pendingSkinHardReload = true; RefreshPlayerAppearance(); }
            } else {
                bool removed = false;
                g_skinToItem[slot] = (toId > 0) ? (uint32_t)toId : 0;
                uint32_t sourceId = (appliedTo > 0) ? (uint32_t)appliedTo : 0;
                if (sourceId == 0 && !deferBind) {
                    if (g_slotTintFrom[slot] > 0) sourceId = g_slotTintFrom[slot];
                    else if (g_slotRetexFrom[slot] > 0) sourceId = g_slotRetexFrom[slot];
                    else if (player && player->descriptors) {
                        uint32_t off = GetVisibleItemField(slot);
                        if (off) {
                            __try { sourceId = *(uint32_t*)((uint8_t*)player->descriptors + off); }
                            __except (EXCEPTION_EXECUTE_HANDLER) { sourceId = 0; }
                        }
                    }
                }
                g_skinAppliedTo[slot] = sourceId;
                if (toId <= 0 && g_slotRetexFrom[slot] > 0) {
                    ColorEngine::ItemRetexRemove(g_slotRetexFrom[slot]);
                    g_slotRetexFrom[slot] = 0; removed = true;
                    g_slotRetexTo[slot] = 0;
                }
                if (!enabled) {
                    memset(&g_skinTint[slot], 0, sizeof(SlotSkinTint));
                    if (g_slotTintFrom[slot] > 0) {
                        ColorEngine::ItemTintSlotRemove((uint32_t)slot);
                        g_slotTintFrom[slot] = 0; removed = true;
                        memset(&g_slotTintApplied[slot], 0, sizeof(SlotSkinTint));
                    }
                } else {
                    g_skinTint[slot].enabled  = 1;
                    g_skinTint[slot].mode     = (uint32_t)mode;
                    g_skinTint[slot].r        = (uint8_t)r;
                    g_skinTint[slot].g        = (uint8_t)g;
                    g_skinTint[slot].b        = (uint8_t)b;
                    g_skinTint[slot].r2       = (uint8_t)r2;
                    g_skinTint[slot].g2       = (uint8_t)g2;
                    g_skinTint[slot].b2       = (uint8_t)b2;
                    g_skinTint[slot].dir      = (uint32_t)dir;
                    g_skinTint[slot].mult     = (uint32_t)mult;
                    g_skinTint[slot].glowStr  = (uint32_t)glowStr;
                    g_skinTint[slot].contrast = (uint32_t)contrast;
                    g_skinTint[slot].span     = (uint32_t)span;
                    g_skinTint[slot].phase    = (uint32_t)phase;
                    g_skinTint[slot].brightness = (uint32_t)brightness;
                    g_skinTint[slot].saturation = (int32_t)saturation;
                    g_skinTint[slot].hueShift   = (uint32_t)hueShift;
                }
                if (removed) { g_pendingSkinHardReload = true; RefreshPlayerAppearance(); }
            }
            UpdateHasSkin();
            SaveFullState(GetPlayerGuid());
            if (!deferBind && player && player->descriptors) {
                uint32_t visId = 0;
                uint32_t off = GetVisibleItemField(slot);
                if (off) {
                    __try { visId = *(uint32_t*)((uint8_t*)player->descriptors + off); }
                    __except (EXCEPTION_EXECUTE_HANDLER) { visId = 0; }
                }
                uint32_t sourceId = g_skinAppliedTo[slot];
                if (sourceId == 0 || sourceId == visId || (g_skinToItem[slot] == 0 && !g_skinTint[slot].enabled)) {
                    if (ApplyPersistedSkins(player)) RefreshPlayerAppearance();
                }
            }
        }
        return false;
    }
    if (strncmp(cmd, "MODELTINT_OFF", 13) == 0) { ColorEngine::SetModelTint(false, 255, 255, 255); return false; }
    if (strncmp(cmd, "MODELTINT:", 10) == 0) {
        int r = 255, g = 255, b = 255; sscanf_s(cmd + 10, "%d:%d:%d", &r, &g, &b);
        ColorEngine::SetModelTint(true, (uint8_t)r, (uint8_t)g, (uint8_t)b);
        return false;
    }
    if (strncmp(cmd, "WORLDTINT_OFF", 13) == 0) { ColorEngine::SetWorldColorTint(false, 255, 255, 255); return false; }
    if (strncmp(cmd, "WORLDTINT:", 10) == 0) {
        int r = 255, g = 255, b = 255; sscanf_s(cmd + 10, "%d:%d:%d", &r, &g, &b);
        ColorEngine::SetWorldColorTint(true, (uint8_t)r, (uint8_t)g, (uint8_t)b);
        return false;
    }
    if (strncmp(cmd, "LIGHTPRESET_OFF", 15) == 0) { ColorEngine::SetLightPreset(-1); return false; }
    if (strncmp(cmd, "LIGHTPRESET:", 12) == 0) { ColorEngine::SetLightPreset(atoi(cmd + 12)); return false; }
    // Absolute world-lighting mood (deterministic in every zone).
    if (strncmp(cmd, "WLIGHT_OFF", 10) == 0) {
        ColorEngine::SetWorldLight(false, 0,0,0, 0,0,0, 0,0,0, 0,0,0, false, 0,0,0);
        return false;
    }
    if (strncmp(cmd, "WLIGHT:", 7) == 0) {
        int a[3] = {255,255,255}, d[3] = {255,255,255}, st[3] = {255,255,255}, sh[3] = {255,255,255};
        int fog = 1, f[3] = {0,0,0};
        sscanf_s(cmd + 7, "%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d",
                 &a[0],&a[1],&a[2], &d[0],&d[1],&d[2], &st[0],&st[1],&st[2],
                 &sh[0],&sh[1],&sh[2], &fog, &f[0],&f[1],&f[2]);
        ColorEngine::SetWorldLight(true,
            (uint8_t)a[0],(uint8_t)a[1],(uint8_t)a[2],
            (uint8_t)d[0],(uint8_t)d[1],(uint8_t)d[2],
            (uint8_t)st[0],(uint8_t)st[1],(uint8_t)st[2],
            (uint8_t)sh[0],(uint8_t)sh[1],(uint8_t)sh[2],
            fog != 0, (uint8_t)f[0],(uint8_t)f[1],(uint8_t)f[2]);
        return false;
    }
    // World brightness (multiplies natural/mood colors; x1000, 1000 = 1.0).
    if (strncmp(cmd, "WBRIGHT_OFF", 11) == 0) { ColorEngine::SetWorldBrightness(false, 1.0f); return false; }
    if (strncmp(cmd, "WBRIGHT:", 8) == 0) {
        int x1000 = 1000; sscanf_s(cmd + 8, "%d", &x1000);
        ColorEngine::SetWorldBrightness(true, (float)x1000 / 1000.0f);
        return false;
    }
    // Weather (engine): type 0=clear,1=rain,2=snow,3=sand ; intensity 0..100.
    if (strncmp(cmd, "WEATHER_OFF", 11) == 0) { ColorEngine::SetWeather(0, 0.0f, true); return false; }
    if (strncmp(cmd, "WEATHER:", 8) == 0) {
        int type = 0, inten = 50; sscanf_s(cmd + 8, "%d:%d", &type, &inten);
        ColorEngine::SetWeather(type, (float)inten / 100.0f, true);
        return false;
    }
    // Skybox override (engine). SKYBOX_LIST asks the DLL to publish every real
    // skybox from LightSkybox.dbc into the Lua global TRANSMORPHER_SKYBOXES.
    if (strncmp(cmd, "SKYBOX_LIST", 11) == 0) { ColorEngine::PublishSkyboxList(); return false; }
    // Publish playable races (live, gear-capable, incl. custom races) to Lua.
    if (strncmp(cmd, "RACE_LIST", 9) == 0) { ColorEngine::PublishRaceList(); return false; }
    // Publish gear-wearing humanoid displays to Lua. Optional cap: HUMANOID_LIST:600
    if (strncmp(cmd, "HUMANOID_LIST", 13) == 0) {
        int cap = 800; if (cmd[13] == ':') sscanf_s(cmd + 14, "%d", &cap);
        ColorEngine::PublishHumanoidList(cap); return false;
    }
    if (strncmp(cmd, "SKYBOX_OFF", 10) == 0) { ColorEngine::SetSkybox(nullptr); return false; }
    if (strncmp(cmd, "SKYBOXID:", 9) == 0) { ColorEngine::SetSkyboxById(atoi(cmd + 9)); return false; }
    if (strncmp(cmd, "SKYBOX:", 7) == 0) { ColorEngine::SetSkybox(cmd + 7); return false; }

    // Over-unit "world text" recolor (numbers/words drawn over a unit in the 3D
    // world). Addressed by engine STYLE so the player's OWN damage colors too.
    //   WTEXT:<style>:<on>:<mode>:<r>:<g>:<b>   (mode 0=solid, 1=rainbow gradient)
    //   WTEXT_SPEED:<cyclesPerSec_x1000>
    //   WTEXT_SIZE:<on>:<factor_x1000>
    //   WTEXT_OFF                               (disable all + restore native size)
    if (strncmp(cmd, "WTEXT_OFF", 9) == 0) { ColorEngine::ClearWorldText(); return false; }
    if (strncmp(cmd, "WTEXT_SPEED:", 12) == 0) {
        int x1000 = 250; sscanf_s(cmd + 12, "%d", &x1000);
        ColorEngine::SetWorldTextGradientSpeed((float)x1000 / 1000.0f);
        return false;
    }
    if (strncmp(cmd, "WTEXT_SIZE:", 11) == 0) {
        int on = 0, x1000 = 1000; sscanf_s(cmd + 11, "%d:%d", &on, &x1000);
        ColorEngine::SetWorldTextSize(on != 0, (float)x1000 / 1000.0f);
        return false;
    }
    if (strncmp(cmd, "WTEXT:", 6) == 0) {
        int style = 0, on = 0, mode = 0, r = 255, g = 255, b = 255;
        sscanf_s(cmd + 6, "%d:%d:%d:%d:%d:%d", &style, &on, &mode, &r, &g, &b);
        ColorEngine::SetWorldTextStyle(style, on != 0, mode, (uint8_t)r, (uint8_t)g, (uint8_t)b);
        return false;
    }
    if (strncmp(cmd, "PTINT_OFF", 9) == 0) { ColorEngine::SetParticleTint(false, 255, 255, 255); return false; }
    if (strncmp(cmd, "PTINT:", 6) == 0) {
        int r = 255, g = 255, b = 255; sscanf_s(cmd + 6, "%d:%d:%d", &r, &g, &b);
        ColorEngine::SetParticleTint(true, (uint8_t)r, (uint8_t)g, (uint8_t)b);
        return false;
    }

    if (strncmp(cmd, "MORPH:", 6) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 6);
        if (id > 0) {
            // NO-OP: If display ID is already set to this value, skip entirely
            if (g_morphDisplay == id) {
                Log("Morph %u already active, skipping (no refresh)", id);
                return false;
            }
            g_morphDisplay = id;

            if (!g_suspended) {
                // MORPH-WHILE-MOUNTED FIX: when mounted, the player's character
                // ("rider") model is attached to the mount, so a plain
                // UpdateDisplayInfo does NOT rebuild its race/creature base — the
                // refresh fires but the new display never shows ("character
                // refreshes but nothing applied"). We must DETACH the rider first
                // so the base model rebuilds to the morph, then RE-ATTACH it.
                // Detect mount from the authoritative native descriptor, not
                // g_morphMount, so this works for ordinary mounts (no mount morph).
                uint32_t curMountId = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
                bool mountedNow = (curMountId > 0);
                if (mountedNow && CGUnit_C_DismountModel) {
                    __try { CGUnit_C_DismountModel(player, 0); } __except(1) {}
                }

                // RACE MORPH FIX: SimplyMorpher3's double-update technique
                // Write dummy display ID (621) and call UpdateDisplayInfo
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = 621;
                if (CGUnit_UpdateDisplayInfo) {
                    ScopedUpdateDisplayInfo(player, 0);
                }

                // Write actual display ID and call UpdateDisplayInfo again
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = id;
                ReapplyActiveBarberTintsForPlayer(player);

                if (CGUnit_UpdateDisplayInfo) {
                    ScopedUpdateDisplayInfo(player, 0);
                }

                // We just did a full model rebuild — cancel any pending deferred
                // login refresh so we never reload the model twice on entering world.
                g_pendingInitialRefreshTicks = 0;

                // For race morphs, refresh equipment slots
                if (IsRaceDisplayID(id)) {
                    for (int s = 1; s <= 19; s++) {
                        if (g_morphItems[s] == 0) {
                            uint32_t off = GetVisibleItemField(s);
                            if (off) {
                                uint32_t currentItem = *(uint32_t*)(desc + off);
                                if (currentItem > 0) {
                                    *(uint32_t*)(desc + off) = currentItem;
                                }
                            }
                        }
                    }
                    Log("Race morph applied displayId=%u (double-update technique)", id);
                } else {
                    Log("Morphed displayId=%u", id);
                }

                // Re-attach the rider to the mount with the freshly rebuilt base
                // model. Honor an active mount morph; otherwise keep the real mount.
                if (mountedNow) {
                    uint32_t targetMount = curMountId;
                    if (g_morphMount == HIDDEN_SENTINEL)      targetMount = 0;
                    else if (g_morphMount > 0)                targetMount = g_morphMount;
                    *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = targetMount;
                    *(uint32_t*)((uint8_t*)player + 0x9C0) = targetMount;
                    if (CGUnit_C_MountModel) {
                        __try { CGUnit_C_MountModel(player, 0, 0); } __except(1) {}
                    }
                    Log("Re-attached rider after base morph (mount=%u)", targetMount);
                }
            } else {
                Log("Morph suspended - state updated (displayId=%u) but not applied", id);
            }
            
            update = true; // Signal that change occurred
        } else if (id == 0) {
             g_morphDisplay = 0;
             if (!g_suspended) {
                 if (g_origDisplay > 0) {
                     *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = g_origDisplay;
                     Log("Character morph reset (orig=%u)", g_origDisplay);
                  } else {
                      uint32_t nativeDisplay = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
                      *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = nativeDisplay;
                      Log("Character morph reset (native=%u)", nativeDisplay);
                  }
                  ReapplyActiveBarberTintsForPlayer(player);
                  update = true;
              }
         }
    }
    else if (strncmp(cmd, "SCALE:", 6) == 0) {
        float scale = (float)atof(cmd + 6);
        if (scale > 0.001f && scale <= 20.0f) {
            // NO-OP: Skip if scale hasn't changed
            if (g_morphScale > scale - 0.001f && g_morphScale < scale + 0.001f) {
                return false;
            }
            g_morphScale = scale;
            if (!g_suspended) {
                *(float*)(desc + 0x10) = scale;
                update = true;
            }
        } else if (scale <= 0.001f) {
            // SCALE:0 RESET logic
            if (g_morphScale <= 0.001f) return false; // Already reset
            g_morphScale = 0.0f;
            if (!g_suspended && g_saved) {
                *(float*)(desc + 0x10) = g_origScale;
                update = true;
            }
            Log("Character scale reset to %f", g_origScale);
        }
    }
    else if (strncmp(cmd, "ITEM:", 5) == 0) {
        int slot = 0; uint32_t itemId = 0;
        if (sscanf_s(cmd + 5, "%d:%u", &slot, &itemId) == 2) {
            if (slot >= 1 && slot <= 19) {
                uint32_t off = GetVisibleItemField(slot);
                if (off) {
                    uint32_t normalized = (itemId == 0) ? HIDDEN_SENTINEL : itemId;
                    // NO-OP: Skip if item hasn't changed
                    if (g_morphItems[slot] == normalized) {
                        return false;
                    }
                    bool morphChanged = true;
                    g_morphItems[slot] = normalized;
                    if (!g_suspended) {
                        *(uint32_t*)(desc + off) = itemId;
                        update = true;
                        if (slot >= 16 && slot <= 18 && morphChanged) g_weaponRefreshTicks = 1;
                    }
                }
            }
        }
    }
    else if (strncmp(cmd, "MOUNT_MORPH:", 12) == 0) {
        int mountIdSigned = atoi(cmd + 12);
        uint32_t newMount = (mountIdSigned == -1) ? HIDDEN_SENTINEL : ((mountIdSigned > 0) ? (uint32_t)mountIdSigned : 0);
        // NO-OP: Skip if mount morph hasn't changed
        if (g_morphMount == newMount) {
            return false;
        }
        g_morphMount = newMount;
        
        if (g_luaMounted == 1) {
            uint32_t targetMount = (g_morphMount == HIDDEN_SENTINEL) ? 0 : g_morphMount;
            *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = targetMount;
            *(uint32_t*)((uint8_t*)player + 0x9C0) = targetMount;
            
            // Clear existing mount model to allow MountModel to trigger
            if (CGUnit_C_DismountModel) {
                __try { CGUnit_C_DismountModel(player, 0); } __except(1) {}
            }
            if (CGUnit_C_MountModel) {
                __try { CGUnit_C_MountModel(player, 0, 0); } __except(1) {}
            }
        }
        update = false;
    }
    else if (strncmp(cmd, "MOUNT_RESET", 11) == 0) {
        g_morphMount = 0;
        
        // Safety: only restore original mount if we are actually mounted.
        // If g_luaMounted == 0, we must force the mount ID to 0 to prevent ghost visuals.
        uint32_t targetMount = (g_luaMounted == 1) ? g_origMount : 0;
        
        *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = targetMount;
        *(uint32_t*)((uint8_t*)player + 0x9C0) = targetMount;
        
        if (targetMount == 0) {
            if (CGUnit_C_DismountModel) {
                __try { CGUnit_C_DismountModel(player, 0); } __except(1) {}
            }
            Log("Mount morph reset: Dismounted (Safety sync)");
        } else {
            if (CGUnit_C_DismountModel) {
                __try { CGUnit_C_DismountModel(player, 0); } __except(1) {}
            }
            if (CGUnit_C_MountModel) {
                __try { CGUnit_C_MountModel(player, 0, 0); } __except(1) {}
            }
            Log("Mount morph reset: Restored original %u", targetMount);
        }
        update = false;
    }
    else if (strncmp(cmd, "SET:MOUNTED:", 12) == 0) {
        uint32_t newMounted = (atoi(cmd + 12) > 0) ? 1 : 0;
        if (newMounted != g_luaMounted) {
            // ANTI-FLICKER: Suppress MorphGuard UpdateDisplayInfo for 10 ticks (500ms)
            // during mount/dismount transitions to let WoW finish its model rebuild
            // and commit the proper "Mount" standby state.
            g_updateCooldown = 10;
            g_lastAppliedMount = 0; // Force re-evaluation after cooldown
        }
        g_luaMounted = newMounted;
        if (newMounted == 0) {
            uint32_t* mountField = (uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
            *mountField = 0;
            *(uint32_t*)((uint8_t*)player + 0x9C0) = 0;
            g_lastAppliedMount = 0;
            if (CGUnit_C_DismountModel) {
                __try { CGUnit_C_DismountModel(player, 0); } __except(1) {}
            }
        }
        // Do NOT call UpdateDisplayInfo on dismount — the server handles it.
        // Calling it here would force a model rebuild that flashes native appearance.
        update = false;
    }
    else if (strncmp(cmd, "PET_MORPH:", 10) == 0) {
        g_morphPet = (uint32_t)atoi(cmd + 10);
        // ... handled in MorphGuard
    }
    else if (strncmp(cmd, "PET_RESET", 9) == 0) {
        g_morphPet = 0;
        // ... handled in MorphGuard
    }
    else if (strncmp(cmd, "HPET_MORPH:", 11) == 0) {
        g_morphHPet = (uint32_t)atoi(cmd + 11);
    }
    else if (strncmp(cmd, "HPET_SCALE:", 11) == 0) {
        float scale = (float)atof(cmd + 11);
        if (scale > 0.05f && scale <= 20.0f) {
            g_morphHPetScale = scale;
        }
    }
    else if (strncmp(cmd, "HPET_RESET", 10) == 0) {
        g_morphHPet = 0;
        g_morphHPetScale = 0.0f;
    }
    else if (strncmp(cmd, "SET:HIDE_PLAYERS_DIST:", 22) == 0) {
        // Distance-based hide: cull radius in yards. Safe to receive any time.
        UnitHider_SetDistance((float)atof(cmd + 22));
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_PLAYERS_ENABLED:", 25) == 0) {
        // Master switch for the whole distance-cull feature.
        UnitHider_SetEnabled(atoi(cmd + 25) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_PLAYERS:", 17) == 0) {
        // Category: other players' bodies.
        UnitHider_SetHidePlayers(atoi(cmd + 17) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_PETS:", 14) == 0) {
        UnitHider_SetHidePets(atoi(cmd + 14) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_NPCS:", 14) == 0) {
        UnitHider_SetHideNpcs(atoi(cmd + 14) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_OBJECTS:", 17) == 0) {
        UnitHider_SetHideObjects(atoi(cmd + 17) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_OTHER_SUMMONS:", 23) == 0) {
        UnitHider_SetHideOtherSummons(atoi(cmd + 23) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_CORPSES:", 17) == 0) {
        UnitHider_SetHideCorpses(atoi(cmd + 17) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_SHOW_GROUP:", 20) == 0) {
        UnitHider_SetShowGroup(atoi(cmd + 20) > 0);
        update = false;
    }
    else if (strncmp(cmd, "HIDE_GROUP_LIST:", 16) == 0) {
        // Comma-separated hex GUIDs of current party/raid members (may be empty).
        UnitHider_SetGroupList(cmd + 16);
        SpellClass_SetGroupList(cmd + 16); // same list classifies spell visuals
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_SHADOWS:", 17) == 0) {
        UnitHider_SetHideShadows(atoi(cmd + 17) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_ALL:", 13) == 0) {
        SetHideAllSpells(atoi(cmd + 13) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:SHOW_OWN_SPELLS:", 20) == 0) {
        SetShowOwnSpells(atoi(cmd + 20) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_PRECAST:", 17) == 0) {
        SetHidePrecast(atoi(cmd + 17) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_CAST:", 14) == 0) {
        SetHideCast(atoi(cmd + 14) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_CHANNEL:", 17) == 0) {
        SetHideChannel(atoi(cmd + 17) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_AURA_START:", 20) == 0) {
        SetHideAuraStart(atoi(cmd + 20) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_AURA_END:", 18) == 0) {
        SetHideAuraEnd(atoi(cmd + 18) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_IMPACT:", 16) == 0) {
        SetHideImpact(atoi(cmd + 16) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_IMPACT_CASTER:", 23) == 0) {
        SetHideImpactCaster(atoi(cmd + 23) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_IMPACT_TARGET:", 23) == 0) {
        SetHideTargetImpact(atoi(cmd + 23) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_AREA_INSTANT:", 22) == 0) {
        SetHideAreaInstant(atoi(cmd + 22) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_AREA_IMPACT:", 21) == 0) {
        SetHideAreaImpact(atoi(cmd + 21) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_AREA_PERSISTENT:", 25) == 0) {
        SetHideAreaPersistent(atoi(cmd + 25) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_MISSILE:", 17) == 0) {
        SetHideMissile(atoi(cmd + 17) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_MISSILE_MARKER:", 24) == 0) {
        SetHideMissileMarker(atoi(cmd + 24) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_SOUND_MISSILE:", 23) == 0) {
        SetHideSoundMissile(atoi(cmd + 23) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SET:HIDE_SOUND_EVENT:", 21) == 0) {
        SetHideSoundEvent(atoi(cmd + 21) > 0);
        SpellMorph_SoftResetCache();
        update = false;
    }
    // ---- SpellClass: global "what to hide" + selected target rows ----
    else if (strncmp(cmd, "SC_ENABLE:", 10) == 0) {
        SpellClass_SetMasterEnabled(atoi(cmd + 10) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SC_GCAT:", 8) == 0) {
        int cat = -1, val = 0;
        if (sscanf_s(cmd + 8, "%d:%d", &cat, &val) == 2)
            SpellClass_SetGlobalCategory(cat, val > 0);
        update = false;
    }
    else if (strncmp(cmd, "SC_HIDEALL:", 11) == 0) {
        SpellClass_SetGlobalHideAll(atoi(cmd + 11) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SC_SEL:", 7) == 0) {
        int row = -1, val = 0;
        if (sscanf_s(cmd + 7, "%d:%d", &row, &val) == 2)
            SpellClass_SetSelected(row, val > 0);
        update = false;
    }
    else if (strncmp(cmd, "SC_RESET", 8) == 0) {
        SpellClass_Reset();
        update = false;
    }
    else if (strncmp(cmd, "SC_BOSSES:", 10) == 0) {
        SpellClass_SetBossList(cmd + 10);
        update = false;
    }
    else if (strncmp(cmd, "SC_BOSSHP:", 10) == 0) {
        SpellClass_SetBossByHealth(atoi(cmd + 10) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SC_ENCHANTS:", 12) == 0) {
        SpellClass_SetHideOtherEnchants(atoi(cmd + 12) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SC_ENCHANTS_NPC:", 16) == 0) {
        SpellClass_SetHideNpcEnchants(atoi(cmd + 16) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SC_SWING:", 9) == 0) {
        SpellClass_SetHideOtherSwing(atoi(cmd + 9) > 0);
        update = false;
    }
    else if (strncmp(cmd, "SC_VDIAG:", 9) == 0) {
        SpellClass_SetVdiag(atoi(cmd + 9));
        update = false;
    }
    else if (strncmp(cmd, "VIS_APPLY:", 10) == 0) {
        Visuals_ApplyToPlayer((uint32_t)atoi(cmd + 10));
        update = false;
    }
    else if (strncmp(cmd, "VIS_REMOVE:", 11) == 0) {
        Visuals_RemoveFromPlayer((uint32_t)atoi(cmd + 11));
        update = false;
    }
    else if (strncmp(cmd, "VIS_REAPPLY", 11) == 0) {
        Visuals_Reapply();
        update = false;
    }
    else if (strncmp(cmd, "VIS_REPLAY:", 11) == 0) {
        Visuals_Replay((uint32_t)atoi(cmd + 11));
        update = false;
    }
    else if (strncmp(cmd, "VIS_AUTOHEAL:", 13) == 0) {
        Visuals_SetAutoHeal(atoi(cmd + 13) > 0);
        update = false;
    }
    else if (strncmp(cmd, "VIS_MUTE:", 9) == 0) {
        Visuals_SetMuteSounds(atoi(cmd + 9) > 0);
        update = false;
    }
    else if (strncmp(cmd, "MUTE_PLAYER_SOUNDS:", 19) == 0) {
        // Units tab "Mute Sound Effects": mute ONLY other players' sounds (footsteps,
        // vocals, spell/combat); keep the local player, NPCs, UI, music and ambient.
        PlayerSoundFilter_SetMuteOtherPlayers(atoi(cmd + 19) > 0);
        update = false;
    }
    else if (strncmp(cmd, "VIS_CLEAR", 9) == 0) {
        Visuals_Clear();
        update = false;
    }
    else if (strncmp(cmd, "VIS_ENUM", 8) == 0) {
        Visuals_EnumerateToLua();
        update = false;
    }
    else if (strncmp(cmd, "SET:CAMERA_FOV:", 15) == 0) {
        SetCameraFov((float)atoi(cmd + 15));
        update = false;
    }

    else if (strncmp(cmd, "ENCHANT_MH:", 11) == 0) {
        uint32_t enchantId = (uint32_t)atoi(cmd + 11);
        // NO-OP: Skip if enchant hasn't changed
        if (g_morphEnchantMH == enchantId && enchantId > 0) {
            return false;
        }
        // Always save the current enchant as original before morphing (unless we already have one)
        if (g_morphEnchantMH == 0 && g_origEnchantMH == 0) {
            g_origEnchantMH = ReadVisibleEnchant(player, 16);
        }
        bool morphChanged = (g_morphEnchantMH != enchantId);
        g_morphEnchantMH = enchantId;
        if (!g_suspended) {
            bool wrote = WriteVisibleEnchant(player, 16, enchantId);
            if (wrote) update = true;
            if (morphChanged || wrote) g_weaponRefreshTicks = 1;
        }
    }
    else if (strncmp(cmd, "ENCHANT_OH:", 11) == 0) {
        uint32_t enchantId = (uint32_t)atoi(cmd + 11);
        // NO-OP: Skip if enchant hasn't changed
        if (g_morphEnchantOH == enchantId && enchantId > 0) {
            return false;
        }
        // Always save the current enchant as original before morphing (unless we already have one)
        if (g_morphEnchantOH == 0 && g_origEnchantOH == 0) {
            g_origEnchantOH = ReadVisibleEnchant(player, 17);
        }
        bool morphChanged = (g_morphEnchantOH != enchantId);
        g_morphEnchantOH = enchantId;
        if (!g_suspended) {
            bool wrote = WriteVisibleEnchant(player, 17, enchantId);
            if (wrote) update = true;
            if (morphChanged || wrote) g_weaponRefreshTicks = 1;
        }
    }
    else if (strncmp(cmd, "ENCHANT_RESET_MH", 16) == 0) {
        bool hadMorph = (g_morphEnchantMH > 0);
        bool restored = false;
        if (g_morphEnchantMH > 0) {
            // If we have a saved original, restore it
            if (g_origEnchantMH > 0) {
                restored = WriteVisibleEnchant(player, 16, g_origEnchantMH) || restored;
            } else {
                restored = WriteVisibleEnchant(player, 16, 0) || restored;
            }
        }
        g_morphEnchantMH = 0;
        g_origEnchantMH = 0;
        
        if (!g_suspended) {
            if (restored) update = true;
            if (hadMorph || restored) g_weaponRefreshTicks = 1;
        }
    }
    else if (strncmp(cmd, "ENCHANT_RESET_OH", 16) == 0) {
        bool hadMorph = (g_morphEnchantOH > 0);
        bool restored = false;
        if (g_morphEnchantOH > 0) {
            if (g_origEnchantOH > 0) {
                restored = WriteVisibleEnchant(player, 17, g_origEnchantOH) || restored;
            } else {
                restored = WriteVisibleEnchant(player, 17, 0) || restored;
            }
        }
        g_morphEnchantOH = 0;
        g_origEnchantOH = 0;
        
        if (!g_suspended) {
            if (restored) update = true;
            if (hadMorph || restored) g_weaponRefreshTicks = 1;
        }
    }
    else if (strncmp(cmd, "TITLE:", 6) == 0) {
        uint32_t titleId = (uint32_t)atoi(cmd + 6);
        if (titleId > 0) {
            if (g_origTitle == 0) {
                g_origTitle = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
            }

            if (g_morphTitle == titleId && *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) == titleId) {
                return false;
            }

            if (!IsTitleKnown(player, titleId)) {
                SetTitleKnown(player, titleId, true);
            }

            g_morphTitle = titleId;
            *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = titleId;

            if (FrameScript_Execute) {
                char luaCmd[256];
                sprintf_s(luaCmd,
                    "if SetCurrentTitle then SetCurrentTitle(%u) elseif PaperDollTitleManager_SetCurrentTitle then PaperDollTitleManager_SetCurrentTitle(%u) end",
                    titleId, titleId);
                FrameScript_Execute(luaCmd, "Transmorpher", 0);
                FrameScript_Execute("if PaperDollTitlesPane_Update then PaperDollTitlesPane_Update() end", "Transmorpher", 0);
            }
            update = true;
        }
    }
    else if (strncmp(cmd, "TITLE_RESET", 11) == 0) {
        uint32_t restoreTitle = g_origTitle;
        g_morphTitle = 0;

        if (player && player->descriptors) {
            uint8_t* desc = (uint8_t*)player->descriptors;
            *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = restoreTitle;

            if (FrameScript_Execute) {
                char luaCmd[256];
                sprintf_s(luaCmd,
                    "if SetCurrentTitle then SetCurrentTitle(%u) elseif PaperDollTitleManager_SetCurrentTitle then PaperDollTitleManager_SetCurrentTitle(%u) end",
                    restoreTitle, restoreTitle);
                FrameScript_Execute(luaCmd, "Transmorpher", 0);
                FrameScript_Execute("if PaperDollTitlesPane_Update then PaperDollTitlesPane_Update() end", "Transmorpher", 0);
            }
        }

        g_origTitle = 0;
        update = true;
    }
    else if (strncmp(cmd, "TIME:", 5) == 0) {
        float val = (float)atof(cmd + 5);
        if (val < 0.0f) UninstallTimeHook();
        else {
            extern float g_timeOfDay;
            g_timeOfDay = val;
            
            // Ensure hook is installed FIRST (sets memory protection)
            extern bool g_timeHookInstalled;
            if (!g_timeHookInstalled) {
                if (!InstallTimeHook()) {
                    Log("ERROR: Failed to install time hook");
                    return false;
                }
            }
            
            // Now safe to write to storage
            __try {
                *(float*)0x0076D000 = val;
            } __except(1) {
                Log("ERROR: Exception writing time to 0x0076D000");
            }
        }
    }
    else if (strncmp(cmd, "SPELL_MORPH:", 12) == 0) {
        uint32_t sourceSpellId = 0;
        uint32_t targetSpellId = 0;
        if (sscanf_s(cmd + 12, "%u:%u", &sourceSpellId, &targetSpellId) == 2) {
            if (!SetSpellMorph(sourceSpellId, targetSpellId)) {
                Log("Spell morph rejected (%u -> %u)", sourceSpellId, targetSpellId);
            }
        }
    }
    else if (strncmp(cmd, "SPELL_RESET:", 12) == 0) {
        uint32_t sourceSpellId = (uint32_t)atoi(cmd + 12);
        if (sourceSpellId > 0) {
            RemoveSpellMorph(sourceSpellId);
        }
    }
    else if (strncmp(cmd, "SPELL_VISUAL_PATCH:", 19) == 0) {
        uint32_t sourceSpellId = 0;
        uint32_t targetSpellId = 0;
        if (sscanf_s(cmd + 19, "%u:%u", &sourceSpellId, &targetSpellId) == 2) {
            PatchSpellVisualId(sourceSpellId, targetSpellId);
            SpellMorph_SoftResetCache();
        }
    }
    else if (strncmp(cmd, "SPELL_VISUAL_RESTORE:", 21) == 0) {
        uint32_t sourceSpellId = (uint32_t)atoi(cmd + 21);
        if (sourceSpellId > 0) {
            RestoreSpellVisualId(sourceSpellId);
            SpellMorph_SoftResetCache();
        }
    }
    else if (strncmp(cmd, "SPELL_SEARCH:", 13) == 0) {
        auto HandleSearch = [](const char* c) {
            if (FrameScript_Execute) {
                std::string q = c + 13;
                std::string res = SearchSpells(q);
                char lCmd[8192];
                sprintf_s(lCmd, sizeof(lCmd), "TRANSMORPHER_SEARCH_RESULTS = '%s'", res.c_str());
                FrameScript_Execute(lCmd, "Transmorpher", 0);
            }
        };
        HandleSearch(cmd);
    }
    else if (strcmp(cmd, "SPELL_DBC_STATUS") == 0) {
        if (FrameScript_Execute) {
            extern size_t GetSpellDBCRecordCount();
            char lCmd[256];
            sprintf_s(lCmd, sizeof(lCmd), "DEFAULT_CHAT_FRAME:AddMessage('|cff00ccff[Transmorpher]|r DLL DBC Status: %zu records loaded')", GetSpellDBCRecordCount());
            FrameScript_Execute(lCmd, "Transmorpher", 0);
        }
    }
    else if (strncmp(cmd, "SPELL_RESET_ALL", 15) == 0) {
        ClearSpellMorphs();
    }
    else if (strncmp(cmd, "SPELL_WHITE_CARD:", 17) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 17);
        SpellMorph_AddWhiteCard(id);
    }
    else if (strcmp(cmd, "SPELL_PLAYER_BOOK_CLEAR") == 0) {
        ClearPlayerSpellbookSpellIds();
    }
    else if (strncmp(cmd, "SPELL_PLAYER_BOOK_ADD:", 22) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 22);
        AddPlayerSpellbookSpellId(id);
    }
    else if (strcmp(cmd, "SPELL_PLAYER_BOOK_COMMIT") == 0) {
        SpellMorph_SoftResetCache();
        update = false;
    }
    else if (strncmp(cmd, "SPELL_WHITE_REMOVE:", 19) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 19);
        SpellMorph_RemoveWhiteCard(id);
    }
    else if (strncmp(cmd, "SPELL_WHITE_CLEAR", 17) == 0) {
        SpellMorph_ClearWhiteCard();
    }
    else if (strncmp(cmd, "SET:PROTECTED_TIER:", 19) == 0) {
        char tierKey[16] = { 0 };
        int enabled = 0;
        if (sscanf_s(cmd + 19, "%15[^:]:%d", tierKey, (unsigned)_countof(tierKey), &enabled) == 2) {
            SetProtectedTierEnabled(tierKey, enabled > 0);
        }
        update = false;
    }
    else if (strcmp(cmd, "SPELL_PROTECTED_DUMP") == 0) {
        PushProtectedSpellResultsToLua();
    }
    else if (strncmp(cmd, "SPELL_PROTECTED_ADD:", 20) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 20);
        if (id > 0) {
            AddProtectedSpellId(id);
        }
    }
    else if (strncmp(cmd, "SPELL_PROTECTED_REMOVE:", 23) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 23);
        if (id > 0) {
            RemoveProtectedSpellId(id);
        }
    }
    else if (strcmp(cmd, "SPELL_PROTECTED_CLEAR") == 0) {
        ClearProtectedSpellIds();
    }
    else if (strcmp(cmd, "SPELL_PROTECTED_SAVE") == 0) {
        bool ok = SaveProtectedSpellIds();
        if (ok) {
            ReloadProtectedSpellIds();
            PushProtectedSpellResultsToLua();
        }
        PushProtectedSaveResultToLua(ok);
    }
    else if (strcmp(cmd, "SPELL_PROTECTED_RELOAD") == 0) {
        ReloadProtectedSpellIds();
        PushProtectedSpellResultsToLua();
    }
    else if (strncmp(cmd, "RESET:", 6) == 0 && cmd[6] >= '0' && cmd[6] <= '9') {
        int slot = 0;
        if (sscanf_s(cmd + 6, "%d", &slot) == 1 && slot >= 1 && slot <= 19) {
            uint32_t off = GetVisibleItemField(slot);
            if (off) {
                bool hadMorph = (g_morphItems[slot] != 0);
                g_morphItems[slot] = 0;
                if (!g_suspended) {
                    *(uint32_t*)(desc + off) = g_origItems[slot];
                    if (hadMorph) {
                        update = true;
                        if (slot >= 16 && slot <= 18) g_weaponRefreshTicks = 1;
                    }
                }
            }
        }
    }
    else if (strncmp(cmd, "RESET:ALL", 9) == 0) {
        g_suspended = false; // Force resume on reset
        ResetAllMorphs();    // restores descriptors AND does its own single rebuild
        update = false;      // avoid a second post-batch rebuild (no burst)
    }
    else if (strncmp(cmd, "RESET:SILENT", 12) == 0) {
        // Clear state without triggering visual updates (safe for logout)
        g_morphDisplay = 0; g_morphScale = 0.0f; g_morphMount = 0;
        g_morphPet = 0; g_morphHPet = 0; g_morphHPetScale = 0.0f;
        g_morphEnchantMH = 0; g_morphEnchantOH = 0; g_morphTitle = 0;
        memset(g_morphItems, 0, sizeof(g_morphItems));
        g_origMount = 0; g_origDisplay = 0; g_origScale = 1.0f;
        g_origPetDisplay = 0; g_origHPetDisplay = 0;
        g_origEnchantMH = 0; g_origEnchantOH = 0;
        g_origTitle = 0;
        memset(g_origItems, 0, sizeof(g_origItems));
        g_saved = false;
        g_hasMorph = false;
        g_suspended = false;
        g_forceCharacterStateReload = true;
        ClearSpellMorphs();
        // Do NOT call ResetAllMorphs or UpdateDisplayInfo
    }
    else if (strncmp(cmd, "SUSPEND", 7) == 0) {
        if (!g_suspended) {
            g_suspended = true;
        }
    }
    else if (strncmp(cmd, "RESUME", 6) == 0) {
        if (g_suspended) {
            g_suspended = false;
            update = true; // Only refresh when actually resuming from suspended
        }

        if (player && player->descriptors) {
            RefreshOriginals(player);
            if (ApplyMorphState(player)) {
                update = true;
            }
        }

        // If RESUME was a no-op, do not force a visual refresh. Login/teleport paths
        // can send RESUME repeatedly after descriptors are already correct; forcing
        // a refresh there creates the delayed blink without changing anything.
    }
    // New Settings Commands
    else if (strncmp(cmd, "SET:DBW:", 8) == 0) {
        g_showDBW = (uint32_t)atoi(cmd + 8);
        Log("DBW setting changed: %u", g_showDBW);
    }
    else if (strncmp(cmd, "SET:META:", 9) == 0) {
        g_showMeta = (uint32_t)atoi(cmd + 9);
        Log("Meta setting changed: %u", g_showMeta);
    }
    else if (strncmp(cmd, "SET:SHAPE:", 10) == 0) {
        g_keepShapeshift = (uint32_t)atoi(cmd + 10);
    }
    else if (strncmp(cmd, "MSDF_MODE:", 10) == 0) {
        int mode = atoi(cmd + 10);
        if (mode < 0) mode = 0;
        if (mode > 1) mode = 1;
        SaveMSDFStateSetting(mode);
        Log("[MSDF] Saved mode %d for next client start", mode);
        Log("[MSDF] Runtime mode change queued to %d for next client start", mode);
        update = false;
    }
    // Multiplayer Sync Bulk Commands
    else if (strncmp(cmd, "PEER_SET:", 9) == 0) {
        uint64_t guid = 0;
        char guidStr[64] = {0};
        uint32_t disp = 0; int sc100 = 0;
        uint32_t mnt = 0, pet = 0, hpet = 0; int hpsc100 = 0;
        uint32_t emh = 0, eoh = 0;
        char itemsStr[512] = {0};

        // Format: PEER_SET:GUID,display,scale100,mount,pet,hpet,hpsc100,emh,eoh,items
        if (sscanf_s(cmd + 9, "%[^,],%u,%d,%u,%u,%u,%d,%u,%u,%s", 
            guidStr, (unsigned)sizeof(guidStr), &disp, &sc100, &mnt, &pet, &hpet, &hpsc100, &emh, &eoh, itemsStr, (unsigned)sizeof(itemsStr)) >= 10) {
            
                guid = strtoull(guidStr, nullptr, 16);
                if (guid != 0) {
                    RemoteMorph& rm = g_remoteMorphs[guid];
                    rm.lastSeen = GetTickCount64();
                    
                    // RESET PEER STATE: Clear existing morph data so new state replaces it completely
                    // instead of incrementally overlaying it. This prevents gear from lingering.
                    rm.displayId = 0;
                    rm.scale = 0.0f;
                    rm.mountId = 0;
                    rm.petId = 0;
                    rm.hPetId = 0;
                    rm.hPetScale = 0.0f;
                    rm.enchantMH = 0;
                    rm.enchantOH = 0;
                    rm.titleId = 0;
                    memset(rm.items, 0, sizeof(rm.items));
                    // Do NOT reset capturedItems/origItems here; the guard will re-capture if needed
                    
                    rm.displayId = disp;
                    rm.scale = (float)sc100 / 100.0f;
                    rm.mountId = (mnt == 4294967295) ? 0 : mnt;
                    rm.petId = pet;
                    rm.hPetId = hpet;
                    rm.hPetScale = (float)hpsc100 / 100.0f;
                    rm.enchantMH = emh;
                    rm.enchantOH = eoh;
                    rm.pendingClear = false;
                
                // Parse items: slot=id-slot=id-...
                char* next_item = nullptr;
                char* item_tok = strtok_s(itemsStr, "-", &next_item);
                while (item_tok) {
                    int slot = 0; uint32_t id = 0;
                    if (sscanf_s(item_tok, "%d=%u", &slot, &id) == 2) {
                        if (slot >= 1 && slot <= 19) {
                            rm.items[slot] = (id == 0) ? HIDDEN_SENTINEL : id;
                            rm.unmorphRelease[slot] = false;
                        }
                    }
                    item_tok = strtok_s(nullptr, "-", &next_item);
                }
                Log("Remote GUID %llX: Peer state updated via PEER_SET (disp=%u)", guid, disp);
            }
        }
    }
    else if (strncmp(cmd, "PEER_CLEAR:", 11) == 0) {
        uint64_t guid = strtoull(cmd + 11, nullptr, 16);
        if (guid != 0) {
            g_remoteMorphs.erase(guid);
            Log("Remote GUID %llX: Peer cleared", guid);
        }
    }
    else if (strncmp(cmd, "PEER_CLEAR_ALL", 14) == 0) {
        uint64_t now = GetTickCount64();
        for (auto& pair : g_remoteMorphs) {
            RemoteMorph& rm = pair.second;
            rm.displayId = 0;
            rm.scale = 0.0f;
            rm.enchantMH = 0;
            rm.enchantOH = 0;
            rm.mountId = 0;
            rm.petId = 0;
            rm.hPetId = 0;
            rm.hPetScale = 0.0f;
            rm.titleId = 0;
            memset(rm.items, 0, sizeof(rm.items));
            memset(rm.unmorphRelease, 0, sizeof(rm.unmorphRelease));
            rm.pendingClear = true;
            rm.lastSeen = now;
        }
        Log("All peers clear requested");
    }

    UpdateHasMorph();
    
    if (shouldPersist) {
        SaveFullState(GetPlayerGuid());
    }
    
    return update;
}

// ================================================================
// LAYER 3: State Guard (MorphGuard)
// Periodically verifies and reapplies state via high-frequency timer.
// ANTI-FLICKER: Uses cooldown + last-applied caching to prevent
// redundant UpdateDisplayInfo calls that cause model redraws.
// ================================================================
void MorphGuard(WowObject* player) {
    if (!player || !player->descriptors) return;
    if ((!g_hasMorph && !g_hasSkin && !g_barberActive) || g_suspended) return;

    // Grace period for login/teleport
    if (!g_justLoggedIn) {
        g_justLoggedIn = true;
        g_loginTicks = 0; 
    }
    
    if (g_loginTicks > 0) {
        g_loginTicks--;
        return;
    }
    
    uint8_t* desc = (uint8_t*)player->descriptors;

    // --- Special Form Detection ---
    uint32_t currentDisplay = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
    uint32_t nativeDisplay = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
    
    bool inSpecialForm = false;
    bool hasActiveMorphDisplay = (g_morphDisplay > 0);
    bool currentIsActiveMorph = hasActiveMorphDisplay && (currentDisplay == g_morphDisplay);
    bool currentIsOriginalDisplay = (currentDisplay == g_origDisplay);
    if (currentDisplay != nativeDisplay && !currentIsActiveMorph && !currentIsOriginalDisplay && currentDisplay != 0 && currentDisplay != 621) {
        // We are in some non-standard form. Check if we should allow it.
        if (currentDisplay == 25277) {
            if (g_showMeta == 1) inSpecialForm = true; // Show Meta -> stay in special form
        } else {
            if (g_keepShapeshift == 0) inSpecialForm = true; // Allow forms -> stay in special form
        }
    }

    // Barber base-model guard. The restyle (skin/face/hair/hair-color/facial) must
    // affect ONLY the base/morph humanoid. Shapeshift forms (Moonkin, Cat, Bear,
    // Travel, Tree, Ghost Wolf...) are a different model AND derive their fur/feather
    // tint from PLAYER_BYTES (hair color) — so leaving the barber bytes stamped bleeds
    // the look into the form. Whenever we're NOT showing the base/morph humanoid we
    // restore the captured ORIGINAL bytes; the barber re-stamps below the moment we're
    // back to the humanoid. Runs regardless of the keep-shapeshift setting.
    bool barberBaseHumanoid = (currentDisplay == nativeDisplay)
                           || (g_morphDisplay > 0 && currentDisplay == g_morphDisplay)
                           || (currentDisplay == g_origDisplay);
    if (g_barberActive && g_barberOrigSaved && !barberBaseHumanoid) {
        bool barberRestored = false;
        __try {
            if (*(uint32_t*)(desc + PLAYER_FIELD_BYTES) != g_barberOrigBytes) {
                *(uint32_t*)(desc + PLAYER_FIELD_BYTES) = g_barberOrigBytes; barberRestored = true;
            }
            if (*(uint8_t*)(desc + PLAYER_FIELD_BYTES2) != g_barberOrigFacial) {
                *(uint8_t*)(desc + PLAYER_FIELD_BYTES2) = g_barberOrigFacial; barberRestored = true;
            }
        } __except (EXCEPTION_EXECUTE_HANDLER) {}
        // Rebuild once (only on the transition into the form, when bytes actually moved)
        // so the form re-renders with its natural color instead of the leaked barber look.
        if (barberRestored) g_pendingSkinRefreshTicks = SKIN_REFRESH_DELAY_TICKS;
    }

    // === CHARACTER MORPH ENFORCEMENT ===
    if (!inSpecialForm) {
        bool descriptorDirty = false;

        // Check display ID (most critical)
        if (g_morphDisplay > 0 && currentDisplay != g_morphDisplay) {
            *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = g_morphDisplay;
            descriptorDirty = true;
        }

        // Player-clone appearance bytes (skin/face/hair/facial hair). When we copy
        // another PLAYER (Copy Target), their look comes from PLAYER_BYTES, NOT the
        // display id — the engine reverts these fields on every refresh/zone, so
        // re-stamp them whenever they drift. Kept in lock-step with the display
        // descriptor so the cloned skin re-renders on WoW's own next rebuild
        // (same anti-flicker contract as the display field above).
        if (g_morphPlayerBytesActive) {
            if (*(uint32_t*)(desc + PLAYER_FIELD_BYTES) != g_morphPlayerBytes) {
                *(uint32_t*)(desc + PLAYER_FIELD_BYTES) = g_morphPlayerBytes;
                descriptorDirty = true;
            }
            if (*(uint8_t*)(desc + PLAYER_FIELD_BYTES2) != g_morphPlayerFacial) {
                *(uint8_t*)(desc + PLAYER_FIELD_BYTES2) = g_morphPlayerFacial;
                descriptorDirty = true;
            }
        } else if (g_barberActive && barberBaseHumanoid) {
            // BARBER: keep the user's chosen base-model look (skin/face/hair/hair
            // color/facial hair) stamped — but ONLY on the base/morph humanoid (the
            // form-restore guard above keeps shapeshift forms untouched). The engine
            // reverts PLAYER_BYTES on every model rebuild/zone, so re-write it whenever
            // it drifts — same anti-flicker contract as the display field (only marks
            // dirty when it genuinely moved).
            CaptureBarberOriginal(player);
            uint32_t want = BarberPackBytes();
            if (*(uint32_t*)(desc + PLAYER_FIELD_BYTES) != want) {
                *(uint32_t*)(desc + PLAYER_FIELD_BYTES) = want;
                descriptorDirty = true;
            }
            if (*(uint8_t*)(desc + PLAYER_FIELD_BYTES2) != g_barberFacial) {
                *(uint8_t*)(desc + PLAYER_FIELD_BYTES2) = g_barberFacial;
                descriptorDirty = true;
            }
        }

        // Check items
        for (int s = 1; s <= 19; s++) {
            if (g_morphItems[s] > 0) {
                uint32_t off = GetVisibleItemField(s);
                if (off) {
                    uint32_t target = (g_morphItems[s] == HIDDEN_SENTINEL) ? 0 : g_morphItems[s];
                    if (*(uint32_t*)(desc + off) != target) {
                        *(uint32_t*)(desc + off) = target;
                        descriptorDirty = true;
                    }
                }
            }
        }

        // Check scale (with mount tolerance)
        if (g_morphScale > 0.01f) {
            float cur = *(float*)(desc + 0x10);
            bool scaleMismatch = false;
            if (g_luaMounted == 1 && g_morphScale > 0.99f && g_morphScale < 1.01f) {
                if (cur < 0.8f || cur > 2.2f) scaleMismatch = true;
            } else {
                if (cur < g_morphScale - 0.001f || cur > g_morphScale + 0.001f) scaleMismatch = true;
            }
            if (scaleMismatch) {
                *(float*)(desc + 0x10) = g_morphScale;
                descriptorDirty = true;
            }
        }

        // The UpdateDisplayInfo injection hook is DISABLED, so MorphGuard is now the
        // authoritative enforcer: when ANY tracked descriptor drifted from our morph
        // state (display / player-bytes / the 19 item slots / scale), commit it with a
        // real model rebuild so the change actually shows. The slots are the source of
        // truth — if a slot is morphed, the model is made to reflect it, on foot AND
        // while mounted. descriptorDirty is only true when something genuinely changed
        // (server re-send, zone/form rebuild), so this is not a per-tick refresh.
        // Reconcile persisted skins against the items now stamped in the descriptor
        // (the loop above wrote the morph items, so visible ids are correct here).
        // This is what makes skins re-bind to the RIGHT item after login / a loadout /
        // a server gear re-send, and clear instantly on reset — no relog, no flicker.
        bool skinDirty = g_hasSkin ? ApplyPersistedSkins(player) : false;
        // s_skinPassWasGearSwap is set by ApplyPersistedSkins when at least one slot's
        // visible item id MOVED in this pass (i.e. the user actually swapped a piece
        // of gear in their inventory, so the engine has already re-streamed that M2
        // when the descriptor was written). For that case the full 4-rebuild
        // RefreshPlayerModelFull is overkill — it disposes the M2 four times in a row
        // and tears the model down for a frame, which is the "character goes invisible
        // for a sec on gear swap" bug. A single component re-attach is enough to push
        // the freshly-registered tint through the BLP decode hook.
        // A binding that was removed (skin cleared) also needs a rebuild even if the
        // skin tables are now empty, so check g_slotRetexFrom drift via the return.

        if (descriptorDirty || skinDirty) {
            g_lastAppliedDisplay = g_morphDisplay > 0 ? g_morphDisplay : currentDisplay;

            // Re-stamp weapon descriptors first (they have their own caching).
            ReStampWeapons(player);

            // Rebuild the character model so display/item/byte/skin changes render.
            // Gear-swap refresh: engine just re-streamed the M2 as part of the
            // descriptor change, so a single component re-attach is enough to
            // re-decode the BLPs through the decode hook with the new tint. Skip
            // the heavy 4-rebuild path (was the source of the swap flicker).
            // Skin-edit refresh (slider drag, re-apply on unchanged item): the
            // body composite still holds the old baked tint in its cache, so we
            // need the full visible-item bounce to release it and re-composite.
            if (skinDirty) {
                if (s_skinPassWasGearSwap) {
                    ForceRefreshComponents(player);
                } else {
                    ForceRefreshComponents(player);
                }
            } else if (CGUnit_UpdateDisplayInfo) {
                ScopedUpdateDisplayInfo(player, 1);
            }

            // MOUNTED: the rider model is attached to the mount and caches its gear,
            // so the rebuild above alone won't update the mounted character. Detect
            // the mount from the authoritative descriptor field (not g_luaMounted) and
            // re-trigger the mount model once so the rider re-reads the enforced state.
            uint32_t curMountId = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
            if (curMountId > 0) {
                if (CGUnit_C_DismountModel) { __try { CGUnit_C_DismountModel(player, 0); } __except(1) {} }
                if (CGUnit_C_MountModel)    { __try { CGUnit_C_MountModel(player, 0, 0); } __except(1) {} }
            }
        }
    }

    // === PET MORPH GUARDS (unchanged logic, just cleaner structure) ===
    
    // --- Pet (critter) morph guard ---
    if (g_morphPet > 0 || g_origPetDisplay > 0) {
        __try {
            uint32_t lo = *(uint32_t*)(desc + UNIT_FIELD_CRITTER);
            uint32_t hi = *(uint32_t*)(desc + UNIT_FIELD_CRITTER + 4);
            uint64_t critterGuid = ((uint64_t)hi << 32) | lo;
            if (critterGuid != 0) {
                WowObject* critter = (WowObject*)GetObjectPtr(critterGuid, TYPEMASK_UNIT, "", 0);
                if (critter && critter->descriptors) {
                    uint8_t* cDesc = (uint8_t*)critter->descriptors;
                    uint32_t curDisp = *(uint32_t*)(cDesc + UNIT_FIELD_DISPLAYID);
                    
                    if (g_morphPet > 0) {
                        if (curDisp != g_morphPet) {
                            if (g_origPetDisplay == 0) g_origPetDisplay = curDisp;
                            *(uint32_t*)(cDesc + UNIT_FIELD_DISPLAYID) = g_morphPet;
                            if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(critter, 1); } __except(1) {}
                        }
                    } else if (g_origPetDisplay > 0) {
                        // RESTORE ORIGINAL
                        if (curDisp != g_origPetDisplay) {
                            *(uint32_t*)(cDesc + UNIT_FIELD_DISPLAYID) = g_origPetDisplay;
                            if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(critter, 1); } __except(1) {}
                            Log("Restored critter to original: %u", g_origPetDisplay);
                        }
                        g_origPetDisplay = 0; // Mission accomplished
                    }
                }
            } else {
                 // Critter disappeared, but if we have an orig captured, maybe it's just gone.
                 // We'll clear the tracking if the server doesn't report a critter anymore.
                 g_origPetDisplay = 0; 
            }
        } __except(1) { g_origPetDisplay = 0; }
    }

    // --- Combat pet guard ---
    if (g_morphHPet > 0 || g_morphHPetScale > 0.0f || g_origHPetDisplay > 0) {
        bool found = false;
        __try {
            uint32_t lo = *(uint32_t*)(desc + UNIT_FIELD_SUMMON);
            uint32_t hi = *(uint32_t*)(desc + UNIT_FIELD_SUMMON + 4);
            uint64_t petGuid = ((uint64_t)hi << 32) | lo;
            if (petGuid != 0) {
                WowObject* pet = (WowObject*)GetObjectPtr(petGuid, TYPEMASK_UNIT, "", 0);
                if (pet && pet->descriptors) {
                    uint8_t* pDesc = (uint8_t*)pet->descriptors;
                    uint32_t curDisp = *(uint32_t*)(pDesc + UNIT_FIELD_DISPLAYID);

                    if (g_morphHPet > 0) {
                        if (curDisp != g_morphHPet) {
                            if (g_origHPetDisplay == 0) g_origHPetDisplay = curDisp;
                            *(uint32_t*)(pDesc + UNIT_FIELD_DISPLAYID) = g_morphHPet;
                            if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(pet, 1); } __except(1) {}
                        }
                    } else if (g_origHPetDisplay > 0) {
                        // RESTORE ORIGINAL
                        if (curDisp != g_origHPetDisplay) {
                            *(uint32_t*)(pDesc + UNIT_FIELD_DISPLAYID) = g_origHPetDisplay;
                            if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(pet, 1); } __except(1) {}
                            Log("Restored combat pet to original: %u", g_origHPetDisplay);
                        }
                    }

                    if (g_morphHPetScale > 0.0f) {
                        float curScale = *(float*)(pDesc + 0x10);
                        if (curScale < g_morphHPetScale - 0.01f || curScale > g_morphHPetScale + 0.01f) {
                            *(float*)(pDesc + 0x10) = g_morphHPetScale;
                        }
                    } else if (g_morphHPet == 0 && g_origHPetDisplay > 0) {
                        // Reset scale if we are resetting the pet morph entirely
                         *(float*)(pDesc + 0x10) = 1.0f; 
                         g_origHPetDisplay = 0; // All restored
                    }
                    found = true;
                }
            } else {
                g_origHPetDisplay = 0; // Pet gone
            }
        } __except(1) { g_origHPetDisplay = 0; }

        if (!found) {
            struct GuardianCtx {
                uint32_t morphDisplay;
                uint32_t* origDisplay;
                float morphScale;
            };
            GuardianCtx ctx = { g_morphHPet, &g_origHPetDisplay, g_morphHPetScale };
            uint64_t pGuid = GetPlayerGuid();
            if (pGuid != 0) {
                ForEachPlayerGuardian(pGuid, [](WowObject* unit, uint8_t* d, void* vctx) {
                    GuardianCtx* c = (GuardianCtx*)vctx;
                    if (c->morphDisplay > 0) {
                        uint32_t curDisp = *(uint32_t*)(d + UNIT_FIELD_DISPLAYID);
                        if (curDisp != c->morphDisplay) {
                            if (*c->origDisplay == 0) *c->origDisplay = curDisp;
                            *(uint32_t*)(d + UNIT_FIELD_DISPLAYID) = c->morphDisplay;
                            if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(unit, 1); } __except(1) {}
                        }
                    }
                    if (c->morphScale > 0.0f) {
                        float curScale = *(float*)(d + 0x10);
                        if (curScale < c->morphScale - 0.01f || curScale > c->morphScale + 0.01f) {
                            *(float*)(d + 0x10) = c->morphScale;
                        }
                    }
                }, &ctx);
            }
        }
    }

    // --- Enchant morph guard ---
    if (g_morphEnchantMH > 0) {
        __try {
            uint32_t curEnchant = ReadVisibleEnchant(player, 16);
            if (curEnchant != g_morphEnchantMH) WriteVisibleEnchant(player, 16, g_morphEnchantMH);
        } __except(1) {}
    }
    if (g_morphEnchantOH > 0) {
        __try {
            uint32_t curEnchant = ReadVisibleEnchant(player, 17);
            if (curEnchant != g_morphEnchantOH) WriteVisibleEnchant(player, 17, g_morphEnchantOH);
        } __except(1) {}
    }

    if (g_morphTitle > 0) {
        __try {
            if (!IsTitleKnown(player, g_morphTitle)) SetTitleKnown(player, g_morphTitle, true);
        } __except(1) {}
    }

    // === MOUNT MORPH GUARD (ANTI-FLICKER) ===
    // Only enforce mount state when cooldown is expired and mount display is active.
    // This prevents flicker while still allowing login-time mount reapply even if
    // Lua mount state arrives late.
    if (g_updateCooldown <= 0) {
        __try {
            uint32_t currentDisp = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
            uint32_t curMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
            
            // DLL-SIDE SAFETY NET: If the game's raw mount descriptor is 0,
            // the player is definitively not mounted. Force g_luaMounted = 0
            // to prevent any stale Lua state from causing visual mount leaking.
            if (curMount == 0 && g_luaMounted == 1) {
                g_luaMounted = 0;
                g_lastAppliedMount = 0;
            }

            // GHOST PROTECTION & LEAKAGE PREVENTION
            // Skip mount morphing if the player is a ghost or if the addon says we are dismounted.
            bool skipMount = (currentDisp == 16543 || currentDisp == 16544 || g_luaMounted == 0);

            if (curMount == 0 || skipMount) {
                g_lastAppliedMount = 0;
            } else {
                // Capture original mount if it's a native ID
                if (curMount != g_morphMount && curMount != HIDDEN_SENTINEL) {
                    g_origMount = curMount;
                }

                uint32_t target = 0;
                if (g_morphMount > 0) {
                    target = (g_morphMount == HIDDEN_SENTINEL) ? 0 : g_morphMount;
                } else {
                    target = g_origMount;
                }
                
                // Only write if value actually changed from what we last applied
                if (target > 0 && curMount != target && target != g_lastAppliedMount) {
                    *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = target;
                    *(uint32_t*)((uint8_t*)player + 0x9C0) = target;
                    g_lastAppliedMount = target;
                    
                    // Trigger ISOLATED refresh (Native sequence to avoid flickering)
                    if (CGUnit_C_DismountModel) {
                        __try { CGUnit_C_DismountModel(player, 0); } __except(1) {}
                    }
                    if (CGUnit_C_MountModel) {
                        __try { CGUnit_C_MountModel(player, 0, 0); } __except(1) {}
                    }
                    Log("Isolated MountGuard Refresh triggered. MountId=%u", target);
                }
            }
        } __except(1) {}
    }
    
    // --- Time hook safety guard ---
    if (g_timeOfDay >= 0.0f) {
        // ...
    }
    
    // Weapon Refresh Ticks
    if (g_weaponRefreshTicks > 0) {
        g_weaponRefreshTicks--;
        ReStampWeapons(player);
        // The engine syncs a morphed weapon's entry as 'attached' without rebuilding the model,
        // so force a fresh detach+re-attach here (only fires on a real change -> no flicker).
        ForceWeaponReattach(player);
    }
}

void GetNearbyPlayers(uint64_t playerGuid, char* outBuffer, size_t maxLen) {
    int count = 0;
    if (maxLen > 0) outBuffer[0] = '\0';
    
    __try {
        uintptr_t clientConnection = *(uintptr_t*)P_CLIENT_CONNECTION;
        if (!clientConnection) return;
        uintptr_t objMgr = *(uintptr_t*)(clientConnection + 0x2ED0);
        if (!objMgr) return;
        
        uintptr_t objPtr = *(uintptr_t*)(objMgr + 0xAC);
        int iterCount = 0;
        while (objPtr != 0 && (objPtr % 2 == 0) && ++iterCount <= 5000) {
            WowObject* current = (WowObject*)objPtr;
            
            if (current->descriptors) {
                uint8_t* desc = (uint8_t*)current->descriptors;
                uint32_t typeMask = ((uint32_t*)desc)[2]; // OBJECT_FIELD_TYPE is at index 2
                
                // Only process players (TYPEMASK_PLAYER = 0x10 = 16)
                if ((typeMask & 16) != 0) {
                    uint64_t guid = *(uint64_t*)(desc); // OBJECT_FIELD_GUID is at offset 0
                    
                    // Exclude local player
                    if (guid != playerGuid) {
                        if (current->vtable) {
                            typedef const char* (__thiscall* GetObjectName_fn)(WowObject*);
                            GetObjectName_fn fn = *(GetObjectName_fn*)(uintptr_t(current->vtable) + 54 * 4);
                            if (fn) {
                                const char* name = nullptr;
                                __try { name = fn(current); } __except(1) {}
                                
                                if (name && name[0] != '\0' && strcmp(name, "Unknown") != 0 && strcmp(name, "UNKNOWN") != 0) {
                                    if (count > 0) strcat_s(outBuffer, maxLen, ",");
                                    strcat_s(outBuffer, maxLen, name);
                                    count++;
                                    
                                    // Limit to 50 players to keep Lua string manageable
                                    if (count >= 50) break;
                                }
                            }
                        }
                    }
                }
            }
            objPtr = *(uintptr_t*)(objPtr + 0x3C); // nextObject is at offset 0x3C
        }
    } __except(1) {}
}

void RemoteMorphGuard() {
    if (g_remoteMorphs.empty() || !IsInWorld()) return;

    uint64_t now = GetTickCount64();
    static uint64_t lastLogTime = 0;
    bool debugLog = (now - lastLogTime > 5000);
    if (debugLog) {
        lastLogTime = now;
    }
    
    // Get local player GUID to prevent applying remote morphs to self
    uint64_t localPlayerGuid = GetPlayerGuid();
    
    uint64_t toErase[256];
    int toEraseCount = 0;

    for (auto& pair : g_remoteMorphs) {
        uint64_t guid = pair.first;
        RemoteMorph& rm = pair.second;

        // SAFETY: Never apply remote morphs to the local player
        if (guid == localPlayerGuid && localPlayerGuid != 0) {
            continue;
        }

        // 1. Process the Player/Unit itself
        WowObject* current = GetObjectPtr(guid, 0x18, __FILE__, __LINE__);
        if (current && current->descriptors) {
            uint8_t* desc = (uint8_t*)current->descriptors;
            
            // GUID VALIDATION: Verify the object's descriptor GUID matches
            // what we expect. This prevents morph leaking when the object 
            // manager reuses pointers for different units.
            uint64_t descGuid = *(uint64_t*)(desc); // OBJECT_FIELD_GUID at offset 0
            if (descGuid != guid) {
                // Object pointer was reused — skip this unit entirely
                continue;
            }
            
            bool changed = false;

            // VEHICLE GUARD (RE-verified, no hardcoded ids): while this player is riding a
            // vehicle (Oculus/Nexus drakes, EoE drakes, ToGC mounts, gunship cannons, encounter
            // vehicles, ...) the engine owns their model — it seats/hides the rider and drives a
            // vehicle-bone setup. Force-writing the morph DISPLAY/SCALE/MOUNT and (worst of all)
            // calling UpdateDisplayInfo to rebuild the model fights that, leaving the rider
            // INVISIBLE. So while mounted on a vehicle we leave the model fields untouched and
            // skip the rebuild; the morph snaps back the moment they dismount (this loop runs
            // every frame). Equipment/title/enchant writes below are model-neutral and harmless,
            // but the rebuild they would trigger is suppressed too (guarded at the bottom).
            const bool inVehicle = IsUnitInVehicle(current);

            // Apply DisplayID
            if (!inVehicle && rm.displayId > 0) {
                uint32_t curDisplay = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
                if (!rm.capturedDisplay) {
                    rm.origDisplayId = curDisplay;
                    rm.capturedDisplay = true;
                }
                if (curDisplay != rm.displayId) {
                    *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = rm.displayId;
                    changed = true;
                }
            } else if (!inVehicle && rm.displayId == 0 && rm.capturedDisplay) {
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = rm.origDisplayId;
                rm.capturedDisplay = false;
                changed = true;
            }

            // Apply Scale
            if (!inVehicle && rm.scale > 0.1f) {
                float curScale = *(float*)(desc + 0x10);
                if (!rm.capturedScale) {
                    rm.origScale = curScale;
                    rm.capturedScale = true;
                }
                if (curScale < rm.scale - 0.01f || curScale > rm.scale + 0.01f) {
                    *(float*)(desc + 0x10) = rm.scale;
                    changed = true;
                }
            } else if (!inVehicle && rm.scale <= 0.1f && rm.capturedScale) {
                *(float*)(desc + 0x10) = rm.origScale;
                rm.capturedScale = false;
                changed = true;
            }

            // Apply Items
            for (int s = 1; s <= 19; s++) {
                uint32_t off = GetVisibleItemField(s);
                if (!off) {
                    if (rm.unmorphRelease[s]) {
                        rm.items[s] = 0;
                        rm.unmorphRelease[s] = false;
                    }
                    continue;
                }
                if (rm.items[s] > 0) {
                    if (!rm.capturedItems[s]) {
                        rm.origItems[s] = *(uint32_t*)(desc + off);
                        rm.capturedItems[s] = true;
                    }
                    uint32_t writeVal = rm.items[s];
                    if (writeVal == 4294967295) writeVal = 0; // Explicit hide
                    if (*(uint32_t*)(desc + off) != writeVal) {
                        *(uint32_t*)(desc + off) = writeVal;
                        changed = true;
                    }
                    if (rm.unmorphRelease[s]) {
                        rm.items[s] = 0;
                        rm.unmorphRelease[s] = false;
                    }
                } else if (rm.capturedItems[s]) {
                    if (*(uint32_t*)(desc + off) != rm.origItems[s]) {
                        *(uint32_t*)(desc + off) = rm.origItems[s];
                        changed = true;
                    }
                    rm.capturedItems[s] = false;
                }
            }

            // Apply Enchants
            if (rm.enchantMH > 0) {
                if (!rm.capturedEnchantMH) {
                    rm.origEnchantMH = ReadVisibleEnchant(current, 16);
                    rm.capturedEnchantMH = true;
                }
                if (ReadVisibleEnchant(current, 16) != rm.enchantMH) {
                    WriteVisibleEnchant(current, 16, rm.enchantMH);
                    changed = true;
                }
            } else if (rm.enchantMH == 0 && rm.capturedEnchantMH) {
                WriteVisibleEnchant(current, 16, rm.origEnchantMH);
                rm.capturedEnchantMH = false;
                changed = true;
            }

            if (rm.enchantOH > 0) {
                if (!rm.capturedEnchantOH) {
                    rm.origEnchantOH = ReadVisibleEnchant(current, 17);
                    rm.capturedEnchantOH = true;
                }
                if (ReadVisibleEnchant(current, 17) != rm.enchantOH) {
                    WriteVisibleEnchant(current, 17, rm.enchantOH);
                    changed = true;
                }
            } else if (rm.enchantOH == 0 && rm.capturedEnchantOH) {
                WriteVisibleEnchant(current, 17, rm.origEnchantOH);
                rm.capturedEnchantOH = false;
                changed = true;
            }

            // Apply Title
            if (rm.titleId > 0) {
                if (!rm.capturedTitle) {
                    rm.origTitleId = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
                    rm.capturedTitle = true;
                }
                if (*(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) != rm.titleId) {
                    *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = rm.titleId;
                    changed = true;
                }
            } else if (rm.titleId == 0 && rm.capturedTitle) {
                *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = rm.origTitleId;
                rm.capturedTitle = false;
                changed = true;
            }

            // Apply Mount (suppressed on a vehicle: the rider's mount display is the engine's
            // to manage while seated — forcing it is part of what hides the rider).
            if (!inVehicle && rm.mountId > 0) {
                if (!rm.capturedMount) {
                    rm.origMountId = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
                    rm.capturedMount = true;
                }
                if (*(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) != rm.mountId) {
                    *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = rm.mountId;
                    changed = true;
                }
            } else if (!inVehicle && rm.mountId == 0 && rm.capturedMount) {
                *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = rm.origMountId;
                rm.capturedMount = false;
                changed = true;
            }

            // Per-unit UpdateDisplayInfo throttle: max once per 200ms. NEVER rebuild the model
            // while the unit is on a vehicle (that rebuild is what makes the rider vanish).
            if (changed && !inVehicle && CGUnit_UpdateDisplayInfo) {
                if (now - rm.lastUpdateCall >= 200) {
                    rm.lastUpdateCall = now;
                    __try { CGUnit_UpdateDisplayInfo((void*)(uintptr_t)current, 1); } __except(EXCEPTION_EXECUTE_HANDLER) {}
                }
            }

            // 2. Process Pets (HPET / PET)
            // HPET (Combat Pet)
            uint64_t petGuid = *(uint64_t*)(desc + UNIT_FIELD_SUMMON);
            if (petGuid != 0) {
                WowObject* pet = GetObjectPtr(petGuid, 0x08, __FILE__, __LINE__);
                if (pet && pet->descriptors) {
                    uint8_t* pdesc = (uint8_t*)pet->descriptors;
                    bool pchanged = false;
                    
                    if (rm.hPetId > 0) {
                        if (!rm.capturedHPet) {
                            rm.origHPetId = *(uint32_t*)(pdesc + UNIT_FIELD_DISPLAYID);
                            rm.capturedHPet = true;
                        }
                        if (*(uint32_t*)(pdesc + UNIT_FIELD_DISPLAYID) != rm.hPetId) {
                            *(uint32_t*)(pdesc + UNIT_FIELD_DISPLAYID) = rm.hPetId;
                            pchanged = true;
                        }
                    } else if (rm.hPetId == 0 && rm.capturedHPet) {
                        *(uint32_t*)(pdesc + UNIT_FIELD_DISPLAYID) = rm.origHPetId;
                        rm.capturedHPet = false;
                        pchanged = true;
                    }

                    if (rm.hPetScale > 0.1f) {
                        if (!rm.capturedHPetScale) {
                            rm.origHPetScale = *(float*)(pdesc + 0x10);
                            rm.capturedHPetScale = true;
                        }
                        float curPScale = *(float*)(pdesc + 0x10);
                        if (curPScale < rm.hPetScale - 0.01f || curPScale > rm.hPetScale + 0.01f) {
                            *(float*)(pdesc + 0x10) = rm.hPetScale;
                            pchanged = true;
                        }
                    } else if (rm.hPetScale <= 0.1f && rm.capturedHPetScale) {
                        *(float*)(pdesc + 0x10) = rm.origHPetScale;
                        rm.capturedHPetScale = false;
                        pchanged = true;
                    }

                    if (pchanged && CGUnit_UpdateDisplayInfo) {
                        __try { CGUnit_UpdateDisplayInfo((void*)(uintptr_t)pet, 1); } __except(EXCEPTION_EXECUTE_HANDLER) {}
                    }
                }
            }

            // PET (Companion)
            uint64_t critterGuid = *(uint64_t*)(desc + UNIT_FIELD_CRITTER);
            if (critterGuid != 0) {
                WowObject* critter = GetObjectPtr(critterGuid, 0x08, __FILE__, __LINE__);
                if (critter && critter->descriptors) {
                    uint8_t* cdesc = (uint8_t*)critter->descriptors;
                    
                    if (rm.petId > 0) {
                        if (!rm.capturedPet) {
                            rm.origPetId = *(uint32_t*)(cdesc + UNIT_FIELD_DISPLAYID);
                            rm.capturedPet = true;
                        }
                        if (*(uint32_t*)(cdesc + UNIT_FIELD_DISPLAYID) != rm.petId) {
                            *(uint32_t*)(cdesc + UNIT_FIELD_DISPLAYID) = rm.petId;
                            if (CGUnit_UpdateDisplayInfo) {
                                __try { CGUnit_UpdateDisplayInfo((void*)(uintptr_t)critter, 1); } __except(EXCEPTION_EXECUTE_HANDLER) {}
                            }
                        }
                    } else if (rm.petId == 0 && rm.capturedPet) {
                        *(uint32_t*)(cdesc + UNIT_FIELD_DISPLAYID) = rm.origPetId;
                        rm.capturedPet = false;
                        if (CGUnit_UpdateDisplayInfo) {
                            __try { CGUnit_UpdateDisplayInfo((void*)(uintptr_t)critter, 1); } __except(EXCEPTION_EXECUTE_HANDLER) {}
                        }
                    }
                }
            }
        }
        
        // Handle pendingClear: revert player to original state and mark for deletion
        if (rm.pendingClear) {
            bool hasCaptured = rm.capturedDisplay || rm.capturedScale || rm.capturedEnchantMH || rm.capturedEnchantOH
                || rm.capturedMount || rm.capturedPet || rm.capturedHPet || rm.capturedHPetScale || rm.capturedTitle;
            if (!hasCaptured) {
                for (int s = 1; s <= 19; ++s) {
                    if (rm.capturedItems[s]) {
                        hasCaptured = true;
                        break;
                    }
                }
            }
            // If nothing is captured anymore, safe to erase
            if (!hasCaptured) {
                if (toEraseCount < 256) {
                    toErase[toEraseCount++] = guid;
                }
            }
        }
    }
    
    // Erase peers that have been fully reverted
    for (int i = 0; i < toEraseCount; ++i) {
        g_remoteMorphs.erase(toErase[i]);
    }

    // Cleanup old remote morphs (10 minute timeout)
    static uint64_t lastCleanup = 0;
    if (now - lastCleanup > 30000) {
        for (auto it = g_remoteMorphs.begin(); it != g_remoteMorphs.end();) {
            if (now - it->second.lastSeen > 600000) it = g_remoteMorphs.erase(it);
            else ++it;
        }
        lastCleanup = now;
    }
}

// ===================================
// End of file
