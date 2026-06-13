#pragma once
#include <cstdint>

// ============================================================================
// Visuals — apply REAL persistent character spell-visuals (Shadowmourne-style
// auras) to the local player on demand, and enumerate which ones actually exist.
// RE basis: RE_VISUALS_FINDINGS.md (wow.exe 3.3.5a 12340).
// ============================================================================

// Apply the persistent state-visual of SpellVisual `visualId` to the LOCAL player and
// remember it. Attached ONCE as a TYPE 8 / duration -1 state kit, so it persists natively
// forever (no polling) — exactly like the engine's own buff-aura visual. Returns true if a
// kit was attached. Safe (SEH-guarded).
bool Visuals_ApplyToPlayer(uint32_t visualId);

// Stop showing one visual: surgically remove ONLY the kit-list nodes that visual spawned
// (every other active visual stays untouched — no flash) and drop it from the active set.
void Visuals_RemoveFromPlayer(uint32_t visualId);

// Re-fire ONE visual surgically (drop its own nodes, re-attach, re-track). For one-shot
// "pose" visuals the user opted to repeat (e.g. Devotion-Aura style). Looping state visuals
// never need this; they persist natively. Driven by the addon on a per-visual cadence.
void Visuals_Replay(uint32_t visualId);

// Remove ALL visuals and restore the character's original, un-visualed state.
void Visuals_Clear();

// Enumerate every SpellVisual id that has a persistent state kit (i.e. a real,
// engine-resolvable character visual). Pushes the list to Lua as
//   TRANSMORPHER_VISUALS = "id:kit,id:kit,..."
// then fires TRANSMORPHER_VISUALS_READY via the addon event shim.
void Visuals_EnumerateToLua();

// Re-attach all currently-active visuals to the player (call after the model is rebuilt
// by a morph / zone change so the visuals "run forever" instead of dropping off).
void Visuals_Reapply();

// True if at least one visual is currently active.
bool Visuals_HasActive();

// Self-healing watchdog: call every game tick. Re-attaches a visual ONLY if its kit nodes
// have actually vanished from the unit (model rebuild / GC / finished one-shot). Alive
// visuals are never touched → no flicker. This is what makes visuals truly permanent without
// any periodic remove+re-add. Safe (SEH-guarded), self-throttled, cheap.
void Visuals_Tick();

// Enable/disable the self-healing watchdog (the "Survive morphs & relogs" toggle). When off,
// applied visuals are session-only and drop on the next model rebuild. Default on.
void Visuals_SetAutoHeal(bool on);

// Mute/unmute the sounds of ONLY the visuals applied here (zeros their SpellVisual +
// SpellVisualKit sound ids, with save/restore). Does not touch global game SFX.
void Visuals_SetMuteSounds(bool on);
