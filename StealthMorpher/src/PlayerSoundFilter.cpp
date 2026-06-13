#include "PlayerSoundFilter.h"
#include "Utils.h"
#include "WoWOffsets.h"
#include "Logger.h"
#include "ShutdownCheck.h"

#include <windows.h>
#include <cstdint>
#include "../third_party/Detours/detours.h"

namespace {

// While true, sounds emitted by OTHER players are dropped. Default OFF (inert).
static volatile LONG g_muteOtherPlayers = 0;
static bool g_installed = false;

// --- Verified CGPlayer_C / CGUnit_C sound emitters (thiscall, `this` in ecx). ---
// Arg counts come from each function's terminal `ret N` (callee stack cleanup):
//   PlayUnitSound        ret 8 -> 2 stack args
//   PlayFoleySound       ret 0 -> 0 stack args
//   HandleSpellEventSound ret 0 -> 0 stack args
//   PlayUnitEventSound   ret 4 -> 1 stack arg
typedef int(__fastcall* PlayUnitSound_t)(void* This, void* edx, int a1, int a2);
typedef int(__fastcall* PlayFoley_t)(void* This, void* edx);
typedef int(__fastcall* PlaySpellEvt_t)(void* This, void* edx);
typedef int(__fastcall* PlayUnitEvt_t)(void* This, void* edx, int a1);

static PlayUnitSound_t oPlayerPlayUnitSound = reinterpret_cast<PlayUnitSound_t>(0x007631A0);
static PlayFoley_t     oPlayerPlayFoley     = reinterpret_cast<PlayFoley_t>(0x007633F0);
static PlaySpellEvt_t  oPlayerSpellEvtSound = reinterpret_cast<PlaySpellEvt_t>(0x00763570);
static PlayUnitEvt_t   oUnitPlayEventSound  = reinterpret_cast<PlayUnitEvt_t>(0x007474B0);

static inline bool MuteOn() { return InterlockedCompareExchange(&g_muteOtherPlayers, 0, 0) != 0; }

// True if `obj` is a player unit (CGObject objType 4) — SEH-guarded pointer walk.
static bool IsPlayerObject(void* obj) {
    if (!obj) return false;
    __try {
        return reinterpret_cast<WowObject*>(obj)->objType == 4;
    } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}

static void* LocalPlayerSafe() {
    __try { return reinterpret_cast<void*>(GetPlayer()); }
    __except (EXCEPTION_EXECUTE_HANDLER) { return nullptr; }
}

// A player-emitted sound should be muted when the feature is on, the emitter is a
// player, and that player is NOT the local player. The local player's own sounds, and
// every non-player emitter (NPCs/creatures, UI, music, ambient), always play.
static inline bool ShouldMute(void* This, bool requirePlayerCheck) {
    if (!MuteOn() || g_isProcessTerminating || !This) return false;
    void* lp = LocalPlayerSafe();
    if (This == lp) return false;                       // never the local player
    if (requirePlayerCheck && !IsPlayerObject(This)) return false; // keep NPC sounds
    return true;
}

int __fastcall hkPlayerPlayUnitSound(void* This, void* edx, int a1, int a2) {
    // CGPlayer_C method: `this` is always a player, so no extra type check needed.
    if (ShouldMute(This, false)) return 0;
    return oPlayerPlayUnitSound(This, edx, a1, a2);
}

int __fastcall hkPlayerPlayFoley(void* This, void* edx) {
    if (ShouldMute(This, false)) return 0;
    return oPlayerPlayFoley(This, edx);
}

int __fastcall hkPlayerSpellEvtSound(void* This, void* edx) {
    if (ShouldMute(This, false)) return 0;
    return oPlayerSpellEvtSound(This, edx);
}

int __fastcall hkUnitPlayEventSound(void* This, void* edx, int a1) {
    // Shared by players AND NPCs: only mute when the emitter is a non-local PLAYER, so
    // NPC/creature combat/event sounds keep playing.
    if (ShouldMute(This, true)) return 0;
    return oUnitPlayEventSound(This, edx, a1);
}

} // namespace

void PlayerSoundFilter_Initialize() {
    if (g_installed) return;
    if (DetourTransactionBegin() != NO_ERROR) return;
    DetourUpdateThread(GetCurrentThread());
    DetourAttach(&(PVOID&)oPlayerPlayUnitSound, hkPlayerPlayUnitSound);
    DetourAttach(&(PVOID&)oPlayerPlayFoley, hkPlayerPlayFoley);
    DetourAttach(&(PVOID&)oPlayerSpellEvtSound, hkPlayerSpellEvtSound);
    DetourAttach(&(PVOID&)oUnitPlayEventSound, hkUnitPlayEventSound);
    LONG s = DetourTransactionCommit();
    g_installed = (s == NO_ERROR);
    Log("[PlayerSoundFilter] hooks %s", g_installed ? "installed" : "FAILED");
}

void PlayerSoundFilter_Shutdown() {
    if (!g_installed) return;
    DetourTransactionBegin();
    DetourUpdateThread(GetCurrentThread());
    DetourDetach(&(PVOID&)oPlayerPlayUnitSound, hkPlayerPlayUnitSound);
    DetourDetach(&(PVOID&)oPlayerPlayFoley, hkPlayerPlayFoley);
    DetourDetach(&(PVOID&)oPlayerSpellEvtSound, hkPlayerSpellEvtSound);
    DetourDetach(&(PVOID&)oUnitPlayEventSound, hkUnitPlayEventSound);
    DetourTransactionCommit();
    g_installed = false;
}

void PlayerSoundFilter_SetMuteOtherPlayers(bool on) {
    InterlockedExchange(&g_muteOtherPlayers, on ? 1 : 0);
}
