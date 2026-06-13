#pragma once
#include <cstdint>

// =============================================================================
// UnitHider — make distant objects (other players, their pets/summons, NPCs,
// ground effects, corpses) effectively NOT EXIST, for a real FPS gain.
//
// Mechanism (fully RE'd from wow.exe 3.3.5a 12340) — two complementary hooks:
//
// 1) HIDE via ShouldRender (CGObject_C vtable idx 36). The scene render dispatch at
//    0x004F8D4C presets two out-params to 0, calls ShouldRender, and renders only
//    when BOTH stay 0 (draw gate at 0x004F8DA9). Forcing *pOutA = 1 removes the
//    object from the draw with NO untextured/white artefact and NO flicker — this
//    is the proven hide. Hooked per type:
//       players  -> CGPlayer_C::ShouldRender 0x00730F30
//       units    -> CGUnit_C::ShouldRender   0x006E0840  (pets/summons/NPCs)
//       objects  -> CGObject_C::ShouldRender 0x00743300  (game/dyn objects, corpses)
//
//    NOTE: skipping the per-object render entry wholesale (an earlier attempt) left
//    the model in the scene UNTEXTURED (white) because GetObjectModel/material setup
//    was skipped — so we must hide via ShouldRender, not by bailing the whole entry.
//
// 2) FPS via Animate (CGUnit_C::Animate 0x0071FD80, vtable idx 35). It runs every
//    frame for every unit BEFORE the draw gate, so it is the always-paid CPU cost
//    (bone/particle work in 0x74A7F0 / 0x71FBF0). For a culled (already hidden)
//    unit we skip that work and return its normal success value (1), keeping the
//    dispatcher's control flow identical to a normal hidden unit.
//
// Decisions are recomputed every frame from the live position + live toggles, so
// disabling a category or moving the slider restores instantly (no reload/latch).
// Unit/player position is the verified direct read *(obj+0xD8)+0x10/14/18; game and
// dynamic objects use the virtual GetPosition (vtable idx 12).
//
// The LOCAL player is NEVER culled, and units the local player owns (own pet,
// vehicle, totems) are never culled either.
// =============================================================================

void UnitHider_Initialize();   // install the RenderObject detour (inert until enabled)
void UnitHider_Shutdown();     // remove the detour (graceful unload only)

void UnitHider_SetEnabled(bool enabled);     // master switch
void UnitHider_SetDistance(float yards);

// Per-category toggles (all gated by the master switch + distance).
void UnitHider_SetHidePlayers(bool enabled); // other players' bodies
void UnitHider_SetHidePets(bool enabled);    // pets/summons/totems/guardians owned by other players
void UnitHider_SetHideNpcs(bool enabled);    // all other (un-owned) creatures
void UnitHider_SetHideObjects(bool enabled); // game objects + dynamic objects (AoE fields, traps, banners — "traces")
void UnitHider_SetHideCorpses(bool enabled); // corpses
void UnitHider_SetHideOtherSummons(bool enabled); // other players' summons (Mirror Images etc.), any distance; totems exempt
// Mirror Images carry no owner GUID on observer clients, so they are additionally
// detected via the engine's own mirror-image cache flag (*(unit+0xD0)+0xD8 bit 0x10,
// the gate used by the client's RequestMirrorImageDataFromServer path @0x00730100).

// Group/raid protection: when enabled, party/raid member character models are never
// culled no matter how far. Their pets/summons are still hideable.
// SetGroupList takes a comma-separated list of hex GUIDs ("0x...,0x...") and replaces
// the protected set.
void UnitHider_SetShowGroup(bool enabled);
void UnitHider_SetGroupList(const char* csvHexGuids);

// Extra global FPS toggle: disable character/object ground shadows (renderObjectShadow
// bit of the engine render-flags global). Applied/reasserted each tick via ApplyGlobals.
void UnitHider_SetHideShadows(bool enabled);
void UnitHider_ApplyGlobals();   // call once per in-world tick (main thread)

// Refresh / clear the cached local-player position + GUID. Call once per tick from
// the main-thread timer while in world (render and the timer share that thread).
void UnitHider_SetLocal(uint64_t localGuid, void* localPlayerObj);
void UnitHider_ClearLocal();

// FPS integration for the spell-visual filter (SpellClass). Returns true when `unit` is
// currently being distance-culled (its model is hidden) so the caller can ALSO suppress that
// unit's ATTACHED spell visuals — auras/buff glows, casts, channels, weapon effects — which
// the engine otherwise keeps ticking and drawing via SpellVisualsTick independently of the
// model's ShouldRender. Without this a "hidden" unit still spends a full per-frame visual cost
// (the "they still drop my FPS even though they're hidden" problem). Only true while a cull
// feature is active; the local player and units it owns are never culled.
bool UnitHider_ShouldCullVisualHost(void* unit);

// Cheap "is any cull feature active" gate, used by the spell-visual Tick suppression so it is a
// pure no-op when distance culling is fully off.
bool UnitHider_CullActive();
