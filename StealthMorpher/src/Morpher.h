#pragma once
#include <windows.h>
#include "WoWOffsets.h"

// Global state variables (declared extern here)
extern DWORD g_playerDescBase;
extern uint32_t g_morphMount;
extern uint32_t g_origDisplay;
extern float g_origScale;
extern bool g_suspended;
extern float g_timeOfDay;

bool DoMorph(const char* cmd, WowObject* player);
void MorphGuard(WowObject* player);
bool ApplyMorphState(WowObject* player);
void ReStampWeapons(WowObject* player);
void UpdateHasMorph();
void ResetAllMorphs(bool forceClearOnly = false);
void SoftResetState(WowObject* player);
void PrimeOriginalState(WowObject* player);
// Runs the deferred initial display refresh once the model system has had time
// to warm up after world entry (prevents the cold-start model-reload crash on
// the first login to a morphed character). Call once per timer tick in world.
void ProcessDeferredInitialRefresh(WowObject* player);
// Fire the coalesced skin/recolor model rebuild after a batch of recolor commands
// has settled (one rebuild per batch -> flicker-free apply/remove, no relog). Call
// once per timer tick in world. Runs independently of MorphGuard.
void ProcessDeferredSkinRefresh(WowObject* player);
// Cancel the deferred login "safety net" refresh once a command batch has already
// rebuilt the model, so entering world never does a second full reload.
void CancelDeferredInitialRefresh();
// Camera FOV control (client-side). degrees<=0 disables (leaves client default).
void SetCameraFov(float degrees);
void ApplyCameraFov();
void SetTime(float val);

// ---- Weapon sheath position override (per slot) -----------------------------
// RE (verified, 3.3.5a 12340): the engine picks where a SHEATHED weapon rests by
// reading the item's "sheathe type" via GetSheatheType @0x758F50 (itemcache DB
// 0xC5D828, record field +0x198), then indexing the jump table @0x4EB128 inside
// the attach helper @0x4EB070 -> M2 attachment point. Mapping (both hands):
//   value 1 -> attach 27 (BACK)   value 3 -> attach 33 (HIP)
//   value 0 or >=5 (e.g. 7) -> attachment -1 = HIDDEN
// We hook GetSheatheType and, for the LOCAL player's main/off-hand item, return the
// chosen value so the weapon (morphed OR original) sheaths Back/Hip/Hidden. slot:
// 0 = main hand, 1 = off hand. value: -1 = natural (no override), else 1/3/7 etc.
void SetSheatheOverride(int slot, int value);
int  SheatheOverrideForItem(uint32_t itemId);          // -1 = no override for this item
extern void* g_oGetSheatheType;                        // Detour trampoline (original)
int __fastcall Morpher_hkGetSheatheType(void* This, void* edx);
void RefreshSheathe();   // re-attach weapons so a sheath change shows at once
extern uint32_t g_morphDisplay;
extern uint32_t g_morphItems[20];
extern float g_morphScale;
extern uint32_t g_morphEnchantMH;
extern uint32_t g_morphEnchantOH;
extern uint32_t g_luaMounted;
extern bool g_forceCharacterStateReload;

// Anti-Flicker Engine
extern int g_updateCooldown;        // Ticks to suppress UpdateDisplayInfo calls
extern uint32_t g_lastAppliedDisplay; // Last display ID written to descriptors
extern uint32_t g_lastAppliedMount;   // Last mount ID written to descriptors

// Full State Persistence (replaces mount-only persistence)
void SaveFullState(uint64_t guid = 0);
void LoadFullState(uint64_t guid = 0);
// Read a character's persisted morph by GUID into out params, without disturbing
// the live in-world state (used by the glue character-select hook).
bool ReadMorphFileForGuid(uint64_t guid, uint32_t* outDisplay, uint32_t outItems[20]);
// Per-slot skin tint parameters. Persisted to the state file and re-applied
// on the character-select doll so saved colors render before entering the world.
#pragma pack(push, 1)
struct SlotSkinTint {
    uint32_t enabled;     // 0 = no tint, 1 = tint active
    uint32_t mode;        // 0 solid, 1 gradient, 2 rainbow, 3 two-tone
    uint8_t  r, g, b;
    uint8_t  r2, g2, b2;
    uint32_t dir;         // 0 vert, 1 horiz, 2 diag
    uint32_t mult;        // 0..300 (x100)
    uint32_t glowStr;     // 0..255
    uint32_t contrast;    // 0..400 (100 neutral)
    uint32_t span;        // 0..400 (100 neutral)
    uint32_t phase;       // 0..255
    // v5 extensions: post-effect color transforms applied after the per-pixel
    // tint is computed. Stored at the end so old v4 saves (which lack these
    // bytes) read as zeros — the v4->v5 read path also forces neutral defaults
    // (brightness=128, saturation=0, hue=0) so the on-screen result is
    // unchanged if a slot is loaded from a legacy save.
    uint32_t brightness;  // 0..255 (128 neutral). 0 = black, 255 = 2x.
    int32_t  saturation;  // -100..100 (0 neutral). -100 = grayscale, +100 = 2x vibrancy.
    uint32_t hueShift;    // 0..255 (0 neutral). Rotates the final pixel hue.
};
#pragma pack(pop)
static_assert(sizeof(SlotSkinTint) == 50, "SlotSkinTint size drifted");
bool ReadSkinFileForGuid(uint64_t guid, uint32_t outSkin[20], SlotSkinTint outTint[20]);
// Read a character's persisted BARBER customization (skin/face/hair/hairColor/
// facialHair) by GUID for the glue character-select doll. Returns true if barber
// was active in the saved state.
bool ReadBarberFileForGuid(uint64_t guid, uint8_t* outSkin, uint8_t* outFace,
                           uint8_t* outHair, uint8_t* outHairColor, uint8_t* outFacial);
// Per-region (0 skin, 1 face, 2 hair, 3 facial) free-RGB barber recolor, persisted in
// a per-guid sidecar file so the COLORS render on the cold-start character-select doll
// (the main state file's reserved[] block is already full). Reuses the proven, fixed-size
// SlotSkinTint layout for the per-region parameters. Returns true if any region is active.
bool ReadBarberTintFileForGuid(uint64_t guid, SlotSkinTint outTint[4]);
void SaveBarberTintFile(uint64_t guid);   // persist the live g_barberTint[4] for this guid
void SetBarberTintRegion(int region, const SlotSkinTint* rec);  // update live mirror (rec=nullptr clears)
void ClearBarberTintMirror();             // clear all four live regions
// HIDDEN_SENTINEL value used in persisted item slots (UINT32_MAX = "hidden").
static const uint32_t TM_HIDDEN_SENTINEL = 0xFFFFFFFFu;

// Behavior Settings (Use uint32_t for safer ASM alignment)
extern uint32_t g_showDBW;
extern uint32_t g_showMeta;
extern uint32_t g_keepShapeshift;

// Debug
extern uint32_t g_debugLastDisplayID;

// ================================================================
// MULTIPLAYER SYNC DATA
// ================================================================
struct RemoteMorph {
    uint32_t displayId = 0;
    uint32_t items[20] = {0};
    float scale = 0.0f;
    uint32_t enchantMH = 0;
    uint32_t enchantOH = 0;
    uint32_t mountId = 0;
    uint32_t petId = 0;
    uint32_t hPetId = 0;
    float hPetScale = 0.0f;
    uint32_t titleId = 0;

    // Cache to restore native visual when a morph is dropped
    bool capturedScale = false; float origScale = 1.0f;
    bool capturedEnchantMH = false; uint32_t origEnchantMH = 0;
    bool capturedEnchantOH = false; uint32_t origEnchantOH = 0;
    bool capturedMount = false; uint32_t origMountId = 0;
    bool capturedPet = false; uint32_t origPetId = 0;
    bool capturedHPet = false; uint32_t origHPetId = 0;
    bool capturedHPetScale = false; float origHPetScale = 1.0f;
    bool capturedTitle = false; uint32_t origTitleId = 0;
    bool capturedDisplay = false; uint32_t origDisplayId = 0;
    bool capturedItems[20] = {false}; uint32_t origItems[20] = {0};
    bool pendingClear = false;
    uint64_t lastSeen = 0;
    uint64_t lastUpdateCall = 0;    // Throttle UpdateDisplayInfo per-unit
    bool unmorphRelease[20] = {false};
};

#include <unordered_map>
#include <string>
extern std::unordered_map<uint64_t, RemoteMorph> g_remoteMorphs;

void RemoteMorphGuard();
void GetNearbyPlayers(uint64_t playerGuid, char* outBuffer, size_t maxLen);

// ================================================================
// MULTIPLAYER SYNC DATA
