#pragma once
#include <windows.h>
#include "WoWOffsets.h"

// Global state variables (declared extern here)
extern DWORD g_playerDescBase;
extern uint32_t g_morphMount;
extern uint32_t g_origMount;
extern bool g_suspended;
extern float g_timeOfDay;

bool DoMorph(const char* cmd, WowObject* player);
void MorphGuard(WowObject* player);
bool ApplyMorphState(WowObject* player);
void ReStampWeapons(WowObject* player);
void UpdateHasMorph();
void ResetAllMorphs(bool forceClearOnly = false);
void SoftResetState();
void SetTime(float val);
void SaveMountMorph();
void LoadMountMorph();
extern uint32_t g_morphDisplay;
extern uint32_t g_morphItems[20];
extern float g_morphScale;
extern uint32_t g_morphEnchantMH;
extern uint32_t g_morphEnchantOH;

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
    bool unmorphRelease[20] = {false};
};

#include <unordered_map>
#include <string>
extern std::unordered_map<uint64_t, RemoteMorph> g_remoteMorphs;

void RemoteMorphGuard();
void GetNearbyPlayers(uint64_t playerGuid, char* outBuffer, size_t maxLen);

// ================================================================
// MULTIPLAYER SYNC DATA
