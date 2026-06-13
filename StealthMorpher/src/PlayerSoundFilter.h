#pragma once

// =============================================================================
// PlayerSoundFilter — mute ONLY the sounds emitted by OTHER players.
//
// The local player's own sounds, NPC / creature sounds, UI sounds, music and
// world / ambient sounds are ALL left playing. This is the "Mute Sound Effects"
// option in the Units tab, retargeted from the old global Sound_EnableSFX CVar
// (which killed every sound effect in the world) to a per-source filter.
//
// Mechanism (verified from wow.exe 3.3.5a 12340 / binana sound+player symbols):
// a player unit's sounds are played through CGPlayer_C thiscalls whose `this` is
// the emitting player. We detour them and, while enabled, drop the call when
// `this` is not the local player:
//   CGPlayer_C::PlayUnitSound         0x007631A0  (vocals / unit sounds)
//   CGPlayer_C::PlayFoleySound        0x007633F0  (footsteps / armor foley)
//   CGPlayer_C::HandleSpellEventSound 0x00763570  (cast / spell-event sounds)
// Combat/event sounds for other players also play through the shared
//   CGUnit_C::PlayUnitEventSound      0x007474B0
// which fires for players AND NPCs, so that one is gated additionally on the
// emitter being a PLAYER (objType==4) so NPC combat sounds are untouched.
//
// The detours are always installed (inert until enabled); the gate is a single
// bool flag, so toggling is instant with no reload.
// =============================================================================

void PlayerSoundFilter_Initialize();
void PlayerSoundFilter_Shutdown();
void PlayerSoundFilter_SetMuteOtherPlayers(bool on);
