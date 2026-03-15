#include "Morpher.h"
#include "WoWOffsets.h"
#include "Utils.h"
#include "Hooks.h"
#include "Logger.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>

// ================================================================
// State Variables
// ================================================================
DWORD g_playerDescBase = 0;
bool g_suspended = false;

// Originals
static uint32_t g_origDisplay = 0;
static uint32_t g_origItems[20] = {0};
float g_origScale = 1.0f; // Made non-static for Hooks.cpp
static float g_origHeight = 0.0f;
static float g_origRadius = 0.0f;
static bool g_saved = false;
uint32_t g_origMount = 0;
static uint32_t g_origPetDisplay = 0;
static uint32_t g_origHPetDisplay = 0;
static uint32_t g_origEnchantMH = 0;
static uint32_t g_origEnchantOH = 0;
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

// Behavior Settings
uint32_t g_showDBW = 1;
uint32_t g_showMeta = 1;
uint32_t g_keepShapeshift = 0;

// Multiplayer Sync Data
std::unordered_map<uint64_t, RemoteMorph> g_remoteMorphs;

// Debug
uint32_t g_debugLastDisplayID = 0;

static const uint32_t HIDDEN_SENTINEL = UINT32_MAX;
static bool g_hasMorph = false;
static int g_weaponRefreshTicks = 0;

// ================================================================
// Mount Morph Persistence — survive relog while mounted
// ================================================================
static const char* MOUNT_PERSIST_FILE = "transmorpher_mount.dat";

void SaveMountMorph() {
    FILE* f = fopen(MOUNT_PERSIST_FILE, "wb");
    if (f) {
        fwrite(&g_morphMount, sizeof(uint32_t), 1, f);
        fclose(f);
        Log("Mount morph persisted: %u", g_morphMount);
    }
}

void LoadMountMorph() {
    FILE* f = fopen(MOUNT_PERSIST_FILE, "rb");
    if (f) {
        uint32_t val = 0;
        if (fread(&val, sizeof(uint32_t), 1, f) == 1 && val > 0) {
            g_morphMount = val;
            Log("Mount morph loaded from persistence: %u", val);
        }
        fclose(f);
    }
}

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

static void SaveOriginals(WowObject* p) {
    if (!p || !p->descriptors || g_saved) return;
    uint8_t* desc = (uint8_t*)p->descriptors;
    
    // FIX: Capture the CURRENT display ID (which might be a shapeshift form), 
    // not the Native ID (which is always Human/Orc).
    // This ensures that when we reset/unmorph, we go back to the correct form (e.g. Cat).
    g_origDisplay = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
    
    g_origMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
    g_origScale = *(float*)(desc + 0x10);
    for (int s = 1; s <= 19; s++) {
        uint32_t off = GetVisibleItemField(s);
        if (off) g_origItems[s] = *(uint32_t*)(desc + off);
    }
    
    uint32_t offMH = GetVisibleEnchantField(16);
    uint32_t offOH = GetVisibleEnchantField(17);
    if (offMH) g_origEnchantMH = *(uint32_t*)(desc + offMH);
    if (offOH) g_origEnchantOH = *(uint32_t*)(desc + offOH);
    
    g_origTitle = *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE);
    
    // Character Geometry (Collision) Preservation
    // Offsets for 3.3.5a 12340: Height (0x7B0), Radius (0x7B4)
    g_origHeight = *(float*)((uint8_t*)p + 0x7B0);
    g_origRadius = *(float*)((uint8_t*)p + 0x7B4);

    g_saved = true;
    Log("Originals saved (DisplayID=%u, Scale=%.2f, Height=%.2f, Radius=%.2f)", 
        g_origDisplay, g_origScale, g_origHeight, g_origRadius);
}

static void RefreshOriginals(WowObject* p) {
    if (!p || !p->descriptors || !g_saved) return;
    uint8_t* desc = (uint8_t*)p->descriptors;

    if (g_morphDisplay == 0) g_origDisplay = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
    if (g_morphMount == 0) g_origMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
    if (g_morphScale <= 0.0f) g_origScale = *(float*)(desc + 0x10);
    
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

// Character Geometry (Collision) Preservation
// Forces the collision box to remain at its original size even when morphed,
// unless a specific scale morph is active.
void RestoreCollision(WowObject* player) {
    if (!player || !g_saved || g_morphDisplay == 0) return;
    
    // Scale multiplication: if no morph scale set, use original scale.
    float currentScale = (g_morphScale > 0.0f) ? g_morphScale : g_origScale;
    
    // Write directly to unit fields responsible for collision
    *(float*)((uint8_t*)player + 0x7B0) = g_origHeight * (currentScale / g_origScale);
    *(float*)((uint8_t*)player + 0x7B4) = g_origRadius * (currentScale / g_origScale);
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

    if (g_morphScale > 0.0f) {
        float current = *(float*)(desc + 0x10);
        if (current < g_morphScale - 0.001f || current > g_morphScale + 0.001f) {
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

    RestoreCollision(player);
    return changed;
}

    static bool g_justLoggedIn = false;
static int g_loginTicks = 0;

// Soft reset: only clear originals/saved flag but keep morph targets.
// This allows the hook to continue intercepting descriptor writes with the
// correct morph values across zone transitions, preventing mount/morph
// resets that require remount/re-morph to fix.
void SoftResetState() {
    g_justLoggedIn = false;

    bool hasLocalMorph = (g_morphDisplay > 0) || (g_morphScale != 0.0f) || (g_morphMount > 0) ||
        (g_morphPet > 0) || (g_morphHPet > 0) || (g_morphEnchantMH > 0) ||
        (g_morphEnchantOH > 0) || (g_morphTitle > 0);
    if (!hasLocalMorph) {
        for (int s = 1; s <= 19; ++s) {
            if (g_morphItems[s] > 0) {
                hasLocalMorph = true;
                break;
            }
        }
    }
    if (!hasLocalMorph) {
        g_origPetDisplay = 0; g_origHPetDisplay = 0;
        g_origEnchantMH = 0; g_origEnchantOH = 0;
        g_origTitle = 0;
        g_origMount = 0; g_origDisplay = 0; g_origScale = 1.0f;
        memset(g_origItems, 0, sizeof(g_origItems));
        g_saved = false;
    }

    g_weaponRefreshTicks = 0;
    g_suspended = false;

    UpdateHasMorph(); // Recalculate from current morph targets
    Log("Soft reset complete");
}

void ResetAllMorphs(bool forceClearOnly) {
    if (forceClearOnly) {
        g_justLoggedIn = false; // Reset login grace period

        // Just clear internal state so we don't accidentally write old values
        g_morphDisplay = 0; g_morphScale = 0.0f; g_morphMount = 0;
        g_morphPet = 0; g_morphHPet = 0; g_morphHPetScale = 0.0f;
        g_morphEnchantMH = 0; g_morphEnchantOH = 0; g_morphTitle = 0;
        SaveMountMorph(); // Clear persistence on character change

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
        g_remoteMorphs.clear();
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
    }
    
    // Clear state
    g_morphDisplay = 0; g_morphScale = 0.0f; g_morphMount = 0;
    g_morphPet = 0; g_morphHPet = 0; g_morphHPetScale = 0.0f;
    g_morphEnchantMH = 0; g_morphEnchantOH = 0; g_morphTitle = 0;
    SaveMountMorph(); // Clear mount persistence on full reset
    
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
    
    // Update visual
    if (CGUnit_UpdateDisplayInfo) {
        if (CGUnit_UpdateDisplayInfo) __try { 
            CGUnit_UpdateDisplayInfo(player, 1);
            RestoreCollision(player); // Re-apply collision right after model update
        } __except(1) {}
    }
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
                rm.pendingClear = true;
                Log("Remote GUID %llX: Reset requested", remoteGuid);
            }
            
            return false; // Don't trigger local player update
        } else {
            Log("Failed to parse remote GUID from: %s", guidStr);
        }
        return false;
    }

    SaveOriginals(player);
    RefreshOriginals(player); 

    uint8_t* desc = (uint8_t*)player->descriptors;
    bool update = false;

    if (strncmp(cmd, "MORPH:", 6) == 0) {
        uint32_t id = (uint32_t)atoi(cmd + 6);
        if (id > 0) {
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
                    __try { CGUnit_UpdateDisplayInfo(player, 0); RestoreCollision(player); }
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
            } else {
                Log("Morph suspended - state updated (displayId=%u) but not applied", id);
            }
            
            update = false; // Already called update internally if needed
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
        if (scale > 0.05f && scale <= 20.0f) {
            g_morphScale = scale;
            if (!g_suspended) {
                *(float*)(desc + 0x10) = scale;
                update = true;
            }
        }
    }
    else if (strncmp(cmd, "ITEM:", 5) == 0) {
        int slot = 0; uint32_t itemId = 0;
        if (sscanf_s(cmd + 5, "%d:%u", &slot, &itemId) == 2) {
            if (slot >= 1 && slot <= 19) {
                uint32_t off = GetVisibleItemField(slot);
                if (off) {
                    uint32_t normalized = (itemId == 0) ? HIDDEN_SENTINEL : itemId;
                    bool morphChanged = (g_morphItems[slot] != normalized);
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
        g_morphMount = (mountIdSigned == -1) ? HIDDEN_SENTINEL : ((mountIdSigned > 0) ? (uint32_t)mountIdSigned : 0);
        SaveMountMorph(); // Persist for relog recovery

        // If the player is currently mounted, force an immediate visual update
        // so mount morph changes take effect without needing to remount.
        if (!g_suspended && player && player->descriptors) {
            uint8_t* d = (uint8_t*)player->descriptors;
            uint32_t curMount = *(uint32_t*)(d + UNIT_FIELD_MOUNTDISPLAYID);
            if (curMount > 0 && g_morphMount > 0) {
                uint32_t target = (g_morphMount == HIDDEN_SENTINEL) ? 0 : g_morphMount;
                if (curMount != target) {
                    *(uint32_t*)(d + UNIT_FIELD_MOUNTDISPLAYID) = target;
                    if (CGUnit_UpdateDisplayInfo) {
                        __try { CGUnit_UpdateDisplayInfo(player, 1); } __except(1) {}
                    }
                    Log("Mount morph applied live: %u -> %u", curMount, target);
                }
            }
        }
        update = false;
    }
    else if (strncmp(cmd, "MOUNT_RESET", 11) == 0) {
        g_morphMount = 0;
        SaveMountMorph(); // Clear persistence
        if (!g_suspended) {
            *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = g_origMount;
            update = true;
        }
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
    else if (strncmp(cmd, "ENCHANT_MH:", 11) == 0) {
        uint32_t enchantId = (uint32_t)atoi(cmd + 11);
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
            g_morphTitle = titleId;
            *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = titleId;
            
            char luaCmd[128];
            sprintf_s(luaCmd, "if SetCurrentTitle then SetCurrentTitle(%u) end", titleId);
            if (FrameScript_Execute) {
                FrameScript_Execute(luaCmd, "Transmorpher", 0);
                FrameScript_Execute("if PaperDollTitlesPane_Update then PaperDollTitlesPane_Update() end", "Transmorpher", 0);
            }
            update = true;
        }
    }
    else if (strncmp(cmd, "TITLE_RESET", 11) == 0) {
        *(uint32_t*)(desc + PLAYER_FIELD_CHOSEN_TITLE) = g_origTitle;

        char luaCmd[128];
        if (g_origTitle > 0) {
            sprintf_s(luaCmd, "if SetCurrentTitle then SetCurrentTitle(%u) end", g_origTitle);
        } else {
            sprintf_s(luaCmd, "if SetCurrentTitle then SetCurrentTitle(-1) end");
        }
        if (FrameScript_Execute) {
            FrameScript_Execute(luaCmd, "Transmorpher", 0);
            FrameScript_Execute("if PaperDollTitlesPane_Update then PaperDollTitlesPane_Update() end", "Transmorpher", 0);
        }
        
        g_morphTitle = 0;
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
    else if (strncmp(cmd, "RESET:ALL", 9) == 0) {
        ResetAllMorphs();
        update = true;
    }
    else if (strncmp(cmd, "RESET:SILENT", 12) == 0) {
        // Clear state without triggering visual updates (safe for logout)
        g_morphDisplay = 0; g_morphScale = 0.0f; g_morphMount = 0;
        g_morphPet = 0; g_morphHPet = 0; g_morphHPetScale = 0.0f;
        g_morphEnchantMH = 0; g_morphEnchantOH = 0; g_morphTitle = 0;
        g_hasMorph = false;
        g_suspended = false;
        // Do NOT call ResetAllMorphs or UpdateDisplayInfo
    }
    else if (strncmp(cmd, "SUSPEND", 7) == 0) {
        g_suspended = true;
    }
    else if (strncmp(cmd, "RESUME", 6) == 0) {
        g_suspended = false;
        update = true;
    }
    // New Settings Commands
    else if (strncmp(cmd, "SET:DBW:", 8) == 0) {
        g_showDBW = (uint32_t)atoi(cmd + 8);
    }
    else if (strncmp(cmd, "SET:META:", 9) == 0) {
        g_showMeta = (uint32_t)atoi(cmd + 9);
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
                rm.displayId = disp;
                rm.scale = (float)sc100 / 100.0f;
                rm.mountId = (mnt == 4294967295) ? 0 : mnt;
                rm.petId = pet;
                rm.hPetId = hpet;
                rm.hPetScale = (float)hpsc100 / 100.0f;
                rm.enchantMH = emh;
                rm.enchantOH = eoh;
                rm.pendingClear = false;
                memset(rm.items, 0, sizeof(rm.items));
                memset(rm.unmorphRelease, 0, sizeof(rm.unmorphRelease));
                
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
            auto it = g_remoteMorphs.find(guid);
            if (it != g_remoteMorphs.end()) {
                RemoteMorph& rm = it->second;
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
                rm.lastSeen = GetTickCount64();
            }
            Log("Remote GUID %llX: Peer clear requested", guid);
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
    return update;
}

void MorphGuard(WowObject* player) {
    if (!player || !player->descriptors) return;
    if (!g_hasMorph || g_suspended) return;

    // Grace period for login/teleport to prevent "beep"
    // Removed delays for an instant feel as Hooks handle the primary protection.
    if (!g_justLoggedIn) {
        g_justLoggedIn = true;
        g_loginTicks = 0; 
    }
    
    if (g_loginTicks > 0) {
        g_loginTicks--;
        // While waiting, just let the hooks handle things silently.
        // Don't force CGUnit_UpdateDisplayInfo here.
        return;
    }
    
    uint8_t* desc = (uint8_t*)player->descriptors;
    bool needsRestore = false;

    // --- Special Form Detection ---
    // If the current display is NOT native AND NOT our morph, the player is in a 
    // special form (Druid Shape, Metamorphosis, Deathbringer buff, etc).
    // In this case, we back off to avoid flickering and breaking game systems.
    uint32_t currentDisplay = *(uint32_t*)(desc + UNIT_FIELD_DISPLAYID);
    uint32_t nativeDisplay = *(uint32_t*)(desc + UNIT_FIELD_NATIVEDISPLAYID);
    bool inSpecialForm = (currentDisplay != nativeDisplay && 
                          currentDisplay != g_morphDisplay && 
                          currentDisplay != 0 &&
                          currentDisplay != 621);

    if (inSpecialForm) {
        // Skip forcing character morphs while in a special form.
        goto skip_character_morph;
    }

    // Check display ID first (most critical)
    if (g_morphDisplay > 0) {
        if (*(uint32_t*)(desc + UNIT_FIELD_DISPLAYID) != g_morphDisplay) {
             needsRestore = true;
        }
    }

    if (!needsRestore) {
        for (int s = 1; s <= 19; s++) {
            if (g_morphItems[s] > 0) {
                uint32_t off = GetVisibleItemField(s);
                if (off) {
                    uint32_t target = (g_morphItems[s] == HIDDEN_SENTINEL) ? 0 : g_morphItems[s];
                    if (*(uint32_t*)(desc + off) != target) {
                        needsRestore = true;
                        break;
                    }
                }
            }
        }
    }

    if (!needsRestore && g_morphScale > 0.0f) {
        float cur = *(float*)(desc + 0x10);
        if (cur < g_morphScale - 0.001f || cur > g_morphScale + 0.001f) needsRestore = true;
    }

    if (needsRestore) {
        // Since hooks are now dynamic and handle DisplayID/Items perfectly, 
        // we just need to ensure ApplyMorphState is called for anything the hooks missed.
        if (ApplyMorphState(player)) {
            if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(player, 1); } __except(1) {}
            ReStampWeapons(player);
        }
    }

skip_character_morph:
    bool extraUpdateNeeded = false;

    // --- Pet (critter) morph guard ---
    if (g_morphPet > 0) {
        __try {
            uint32_t lo = *(uint32_t*)(desc + UNIT_FIELD_CRITTER);
            uint32_t hi = *(uint32_t*)(desc + UNIT_FIELD_CRITTER + 4);
            uint64_t critterGuid = ((uint64_t)hi << 32) | lo;
            if (critterGuid != 0) {
                WowObject* critter = (WowObject*)GetObjectPtr(critterGuid, TYPEMASK_UNIT, "", 0);
                if (critter && critter->descriptors) {
                    uint8_t* cDesc = (uint8_t*)critter->descriptors;
                    uint32_t curDisp = *(uint32_t*)(cDesc + UNIT_FIELD_DISPLAYID);
                    if (curDisp != g_morphPet) {
                        if (g_origPetDisplay == 0) g_origPetDisplay = curDisp;
                        *(uint32_t*)(cDesc + UNIT_FIELD_DISPLAYID) = g_morphPet;
                        if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(critter, 1); } __except(1) {}
                    }
                }
            }
        } __except(1) {}
    }

    // --- Combat pet guard ---
    if (g_morphHPet > 0 || g_morphHPetScale > 0.0f) {
        bool found = false;
        __try {
            uint32_t lo = *(uint32_t*)(desc + UNIT_FIELD_SUMMON);
            uint32_t hi = *(uint32_t*)(desc + UNIT_FIELD_SUMMON + 4);
            uint64_t petGuid = ((uint64_t)hi << 32) | lo;
            if (petGuid != 0) {
                WowObject* pet = (WowObject*)GetObjectPtr(petGuid, TYPEMASK_UNIT, "", 0);
                if (pet && pet->descriptors) {
                    uint8_t* pDesc = (uint8_t*)pet->descriptors;
                    if (g_morphHPet > 0) {
                        uint32_t curDisp = *(uint32_t*)(pDesc + UNIT_FIELD_DISPLAYID);
                        if (curDisp != g_morphHPet) {
                            if (g_origHPetDisplay == 0) g_origHPetDisplay = curDisp;
                            *(uint32_t*)(pDesc + UNIT_FIELD_DISPLAYID) = g_morphHPet;
                            if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(pet, 1); } __except(1) {}
                        }
                    }
                    if (g_morphHPetScale > 0.0f) {
                        float curScale = *(float*)(pDesc + 0x10);
                        if (curScale < g_morphHPetScale - 0.01f || curScale > g_morphHPetScale + 0.01f) {
                            *(float*)(pDesc + 0x10) = g_morphHPetScale;
                        }
                    }
                    found = true;
                }
            }
        } __except(1) {}

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

    // --- Mount morph guard ---
    if (g_morphMount > 0) {
        __try {
            uint32_t curMount = *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID);
            uint32_t target = (g_morphMount == HIDDEN_SENTINEL) ? 0 : g_morphMount;
            
            // Only enforce if we are actually mounted (curMount > 0) 
            // OR if it's currently a morph we want to clear.
            if (curMount > 0 && curMount != target) {
                 *(uint32_t*)(desc + UNIT_FIELD_MOUNTDISPLAYID) = target;
                 extraUpdateNeeded = true;
            }
        } __except(1) {}
    }
    
    if (extraUpdateNeeded) {
        if (CGUnit_UpdateDisplayInfo) __try { CGUnit_UpdateDisplayInfo(player, 1); } __except(1) {}
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

    RestoreCollision(player);
}

void GetNearbyPlayers(uint64_t playerGuid, char* outBuffer, size_t maxLen) {
    int count = 0;
    if (maxLen > 0) outBuffer[0] = '\0';
    
    __try {
        uint32_t clientConnection = *(uint32_t*)P_CLIENT_CONNECTION;
        if (!clientConnection) return;
        uint32_t objMgr = *(uint32_t*)(clientConnection + 0x2ED0);
        if (!objMgr) return;
        
        uint32_t objPtr = *(uint32_t*)(objMgr + 0xAC);
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
                            GetObjectName_fn fn = *(GetObjectName_fn*)(current->vtable + 54 * 4);
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
            objPtr = *(uint32_t*)(objPtr + 0x3C); // nextObject is at offset 0x3C
        }
    } __except(1) {}
}

void RemoteMorphGuard() {
    if (g_remoteMorphs.empty() || !IsInWorld()) return;

    uint64_t now = GetTickCount64();
    uint64_t toErase[256] = {0};
    int toEraseCount = 0;
    static uint64_t lastLogTime = 0;
    bool debugLog = (now - lastLogTime > 5000);
    if (debugLog) {
        lastLogTime = now;
    }

    for (auto& pair : g_remoteMorphs) {
        uint64_t guid = pair.first;
        RemoteMorph& rm = pair.second;

        // 1. Process the Player/Unit itself
        WowObject* current = GetObjectPtr(guid, 0x18, __FILE__, __LINE__);
        if (current && current->descriptors) {
            uint8_t* desc = (uint8_t*)current->descriptors;
            bool changed = false;

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
                    if (writeVal == 4294967295) writeVal = 0;
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

            if (changed && CGUnit_UpdateDisplayInfo) {
                __try { CGUnit_UpdateDisplayInfo((void*)(uintptr_t)current, 1); } __except(EXCEPTION_EXECUTE_HANDLER) {}
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
                if (!hasCaptured) {
                    if (toEraseCount < 256) {
                        toErase[toEraseCount++] = guid;
                    }
                }
            }
        }
    }

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
