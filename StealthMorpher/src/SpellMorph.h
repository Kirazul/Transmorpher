#pragma once
#include <cstdint>
#include <cstddef>
#include <string>

struct SpellMorphPair {
    uint32_t sourceSpellId;
    uint32_t targetSpellId;
};

bool InstallSpellVisualHook();
void UninstallSpellVisualHook();

bool SetSpellMorph(uint32_t sourceSpellId, uint32_t targetSpellId);
void RemoveSpellMorph(uint32_t sourceSpellId);
void ClearSpellMorphs();
bool HasSpellMorphs();

void PatchSpellVisualId(uint32_t sourceSpellId, uint32_t targetSpellId);
void RestoreSpellVisualId(uint32_t sourceSpellId);

size_t ExportSpellMorphPairs(SpellMorphPair* outPairs, size_t maxPairs);
void ImportSpellMorphPairs(const SpellMorphPair* pairs, size_t count);

std::string SearchSpells(const std::string& query);
std::string ExportProtectedSpellIds();
bool AddProtectedSpellId(uint32_t spellId);
bool RemoveProtectedSpellId(uint32_t spellId);
void ClearProtectedSpellIds();
bool SaveProtectedSpellIds();
void ReloadProtectedSpellIds();
void AddPlayerSpellbookSpellId(uint32_t spellId);
void ClearPlayerSpellbookSpellIds();
extern size_t GetSpellDBCRecordCount();

// Visibility Controls (Global & Ultra-Granular)
void SetHideAllSpells(bool hide);
void SetShowOwnSpells(bool show);
void SetHidePrecast(bool hide);
void SetHideCast(bool hide);
void SetHideChannel(bool hide);
void SetHideAuraStart(bool hide);
void SetHideAuraEnd(bool hide);
void SetHideImpact(bool hide);
void SetHideImpactCaster(bool hide);
void SetHideTargetImpact(bool hide);
void SetHideAreaInstant(bool hide);
void SetHideAreaImpact(bool hide);
void SetHideAreaPersistent(bool hide);
void SetHideMissile(bool hide);
void SetHideMissileMarker(bool hide);
void SetHideSoundMissile(bool hide);
void SetHideSoundEvent(bool hide);

void SpellMorph_SoftResetCache();

extern "C" {
    __declspec(dllexport) void SpellMorph_AddWhiteCard(int spellId);
    __declspec(dllexport) void SpellMorph_RemoveWhiteCard(int spellId);
    __declspec(dllexport) void SpellMorph_ClearWhiteCard();
}

bool GetHideAllSpells();
bool GetShowOwnSpells();
bool GetHidePrecast();
bool GetHideCast();
bool GetHideChannel();
bool GetHideAuraStart();
bool GetHideAuraEnd();
bool GetHideImpact();
bool GetHideImpactCaster();
bool GetHideTargetImpact();
bool GetHideAreaInstant();
bool GetHideAreaImpact();
bool GetHideAreaPersistent();
bool GetHideMissile();
bool GetHideMissileMarker();
bool GetHideSoundMissile();
bool GetHideSoundEvent();
