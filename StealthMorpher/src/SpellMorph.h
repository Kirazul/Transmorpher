#pragma once
#include <cstdint>
#include <cstddef>

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

size_t ExportSpellMorphPairs(SpellMorphPair* outPairs, size_t maxPairs);
void ImportSpellMorphPairs(const SpellMorphPair* pairs, size_t count);
#include <string>
std::string SearchSpells(const std::string& query);
extern size_t GetSpellDBCRecordCount();
