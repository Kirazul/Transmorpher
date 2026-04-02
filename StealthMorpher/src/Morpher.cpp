#include "Morpher.h"
#include "WoWOffsets.h"
#include "Utils.h"
#include "Hooks.h"
#include "Logger.h"
#include "SpellMorph.h"
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

// Active Morphs
uint32_t g_morphDisplay = 0; // Made global for Hooks.cpp
uint32_t g_morphItems[20] = {0}; // Made global
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
static int g_weaponRefreshTicks = 0;

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

// ================================================================
// FULL STATE PERSISTENCE
// Saves ALL morph targets to disk atomically so morphs survive
// full client restarts without needing /reload or Lua restoration.
// ================================================================
static const uint32_t STATE_FILE_MAGIC = 0x544D5246; // 'TMRF'
static const uint32_t STATE_FILE_VERSION = 3;
static const uint32_t MAX_PERSISTED_SPELL_MORPHS = 128;

static char g_dllDir[MAX_PATH] = {0};
static bool g_initialRefreshDone = false;
static uint64_t g_lastLoadedGuid = 0;

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
                size_t pairCount = (size_t)state.spellMorphCount;
                if (pairCount > MAX_PERSISTED_SPELL_MORPHS) pairCount = MAX_PERSISTED_SPELL_MORPHS;
                ImportSpellMorphPairs(state.spellMorphs, pairCount);
                UpdateHasMorph();
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

// IsTitleKnown and SetTitleKnown are defined in Utils.cpp

bool ApplyMorphState(WowObject* player) {
    if (!player || !player->descriptors) return false;
    uint8_t* desc = (uint8_t*)player->descriptors;
    bool changed = false;

    if (g_morphDisplay > 0) {
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
            changed = true;
        }
    }

    if (g_morphScale > 0.01f) {
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

    // ROBUST LOGIN: Ensure all morph targets are written to descriptors BEFORE the refresh
    if (g_hasMorph && player && !g_initialRefreshDone) {
        // 1. Enforce character/item/scale state
        ApplyMorphState(player);
        
        // 2. Trigger the ONE safety visual refresh for BASE morph (settle character scale first)
        if (CGUnit_UpdateDisplayInfo) {
            g_initialRefreshDone = true;
            __try { CGUnit_UpdateDisplayInfo(player, 1); } __except(1) {}
            Log("Step 1: Base character refresh (Hard Force) triggered. MorphId=%u", g_morphDisplay);
        }

        // 3. Enforce mount state manually AFTER character is scaled (Isolated Refresh)
        if (g_morphMount > 0 && player->descriptors) {
            uint8_t* desc = (uint8_t*)player->descriptors;
            uint32_t currentMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
            
            // Only trigger if actually mounted on the server
            if (currentMount > 0) {
                uint32_t targetMount = (g_morphMount == HIDDEN_SENTINEL) ? 0 : g_morphMount;
                *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = targetMount;
                *(uint32_t*)((uint8_t*)player + 0x9C0) = targetMount;
                g_lastAppliedMount = targetMount;
                
                // Trigger ISOLATED mount update
                if (CGUnit_C_DismountModel) {
                    __try { CGUnit_C_DismountModel(player, 0); } __except(1) {}
                }
                if (CGUnit_C_MountModel) {
                    __try { CGUnit_C_MountModel(player, 0, 0); } __except(1) {}
                }
                Log("Step 2: Isolated Mount Refresh triggered (Ordered). MountId=%u", targetMount);
            } else {
                g_lastAppliedMount = 0;
            }
        }
    }

    Log("Soft reset complete");
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

        g_weaponRefreshTicks = 0;
        g_hasMorph = false;
        g_suspended = false;
        g_saved = false;
        g_initialRefreshDone = false; // PER-CHARACTER REFRESH: Allow new character to trigger a visual refresh
        g_lastLoadedGuid = 0;        // Reset tracking so we can reload the same character if needed
        g_remoteMorphs.clear();
        ClearSpellMorphs();
        return;
    }

    WowObject* player = GetPlayer();
    if (!player || !player->descriptors) return;
    uint8_t* desc = (uint8_t*)player->descriptors;

    if (g_saved) {
        uint32_t nativeDisplay = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
        if (g_origDisplay > 0) {
            *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = g_origDisplay;
        } else {
            *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = nativeDisplay;
        }
        
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
    if (CGUnit_UpdateDisplayInfo) {
        if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(player, 1); } __except(1) {}
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
                // RACE MORPH FIX: SimplyMorpher3's double-update technique
                // Write dummy display ID (621) and call UpdateDisplayInfo
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = 621;
                if (CGUnit_UpdateDisplayInfo) {
                    __try { CGUnit_UpdateDisplayInfo(player, 0); } 
                    __except(EXCEPTION_EXECUTE_HANDLER) { Log("UpdateDisplayInfo exception (dummy)"); }
                }
                
                // Write actual display ID and call UpdateDisplayInfo again
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = id;
                
                if (CGUnit_UpdateDisplayInfo) {
                    __try { CGUnit_UpdateDisplayInfo(player, 0); }
                    __except(EXCEPTION_EXECUTE_HANDLER) { Log("UpdateDisplayInfo exception (actual)"); }
                }
                
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

                if (g_morphMount > 0) {
                    uint32_t curMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
                    if (curMount > 0) {
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
                        Log("Re-applied mount morph %u after base morph", targetMount);
                    }
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
    else if (strncmp(cmd, "SPELL_WHITE_REMOVE:", 19) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 19);
        SpellMorph_RemoveWhiteCard(id);
    }
    else if (strncmp(cmd, "SPELL_WHITE_CLEAR", 17) == 0) {
        SpellMorph_ClearWhiteCard();
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
        ResetAllMorphs();
        update = true;
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
        bool wasSuspended = g_suspended;
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

        if (!wasSuspended && g_hasMorph) {
            update = true;
        }
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
    if (!g_hasMorph || g_suspended) return;

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

    // === CHARACTER MORPH ENFORCEMENT ===
    if (!inSpecialForm) {
        bool descriptorDirty = false;

        // Check display ID (most critical)
        if (g_morphDisplay > 0 && currentDisplay != g_morphDisplay) {
            *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = g_morphDisplay;
            descriptorDirty = true;
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

        // With the UpdateDisplayInfoHook installed, we do NOT need to call 
        // UpdateDisplayInfo from MorphGuard. The hook enforces our values
        // INSIDE WoW's own UpdateDisplayInfo calls, so the morph is applied
        // during WoW's model rebuild — not after it. This eliminates all visual refreshes.
        //
        // Only call UpdateDisplayInfo if item descriptors changed (for equipment model updates)
        // NOTE: Display morph changes are handled by the hook, not here.
        if (descriptorDirty) {
            // Track last applied for logging
            g_lastAppliedDisplay = g_morphDisplay > 0 ? g_morphDisplay : currentDisplay;
            // Weapon refresh only — not a full model rebuild
            ReStampWeapons(player);
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

            // Apply DisplayID
            if (rm.displayId > 0) {
                uint32_t curDisplay = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
                if (!rm.capturedDisplay) {
                    rm.origDisplayId = curDisplay;
                    rm.capturedDisplay = true;
                }
                if (curDisplay != rm.displayId) {
                    *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = rm.displayId;
                    changed = true;
                }
            } else if (rm.displayId == 0 && rm.capturedDisplay) {
                *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) = rm.origDisplayId;
                rm.capturedDisplay = false;
                changed = true;
            }

            // Apply Scale
            if (rm.scale > 0.1f) {
                float curScale = *(float*)(desc + 0x10);
                if (!rm.capturedScale) {
                    rm.origScale = curScale;
                    rm.capturedScale = true;
                }
                if (curScale < rm.scale - 0.01f || curScale > rm.scale + 0.01f) {
                    *(float*)(desc + 0x10) = rm.scale;
                    changed = true;
                }
            } else if (rm.scale <= 0.1f && rm.capturedScale) {
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

            // Apply Mount
            if (rm.mountId > 0) {
                if (!rm.capturedMount) {
                    rm.origMountId = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
                    rm.capturedMount = true;
                }
                if (*(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) != rm.mountId) {
                    *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = rm.mountId;
                    changed = true;
                }
            } else if (rm.mountId == 0 && rm.capturedMount) {
                *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = rm.origMountId;
                rm.capturedMount = false;
                changed = true;
            }

            // Per-unit UpdateDisplayInfo throttle: max once per 200ms
            if (changed && CGUnit_UpdateDisplayInfo) {
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
