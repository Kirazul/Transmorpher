#pragma once
#include <windows.h>
#include <cstdint>
#include "WoWOffsets.h"

// Note: WowObject struct is defined in WoWOffsets.h now

void* GetLuaState();
uint64_t GetPlayerGuid();
WowObject* GetPlayer();
WowObject* GetObjectPtr(uint64_t guid, uint32_t typemask, const char* file, uint32_t line);

// Lua functions
typedef int  (__cdecl* FrameScript_Execute_fn)(const char*, const char*, int);
extern FrameScript_Execute_fn FrameScript_Execute;

typedef void (__cdecl* lua_getfield_fn)(void* L, int idx, const char* k);
extern lua_getfield_fn wow_lua_getfield;

typedef const char* (__cdecl* lua_tolstring_fn)(void* L, int idx, size_t* len);
extern lua_tolstring_fn wow_lua_tolstring;

typedef void (__cdecl* lua_settop_fn)(void* L, int idx);
extern lua_settop_fn wow_lua_settop;

// Additional Lua C API for function registration
typedef double (__cdecl* lua_tonumber_fn)(void* L, int idx);
extern lua_tonumber_fn wow_lua_tonumber;

typedef void (__cdecl* lua_pushcclosure_fn)(void* L, void* fn, int n);
extern lua_pushcclosure_fn wow_lua_pushcclosure;

typedef void (__cdecl* lua_setfield_fn)(void* L, int idx, const char* k);
extern lua_setfield_fn wow_lua_setfield;

typedef void (__cdecl* lua_pushstring_fn)(void* L, const char* s);
extern lua_pushstring_fn wow_lua_pushstring;

typedef void (__cdecl* lua_pushnumber_fn)(void* L, double n);
extern lua_pushnumber_fn wow_lua_pushnumber;

typedef int (__cdecl* lua_gettop_fn)(void* L);
extern lua_gettop_fn wow_lua_gettop;

typedef int (__cdecl* lua_type_fn)(void* L, int idx);
extern lua_type_fn wow_lua_type;

// Update Display Info
typedef void(__thiscall* UpdateDisplayInfo_fn)(void* thisPtr, uint32_t unk);
extern UpdateDisplayInfo_fn CGUnit_UpdateDisplayInfo;

#define LUA_GLOBALSINDEX (-10002)

uint32_t ReadVisibleEnchant(WowObject* unit, int slot);
bool WriteVisibleEnchant(WowObject* unit, int slot, uint32_t enchantId);

bool IsRaceDisplayID(uint32_t displayId);

// Title Helpers
bool IsTitleKnown(WowObject* player, uint32_t titleId);
void SetTitleKnown(WowObject* player, uint32_t titleId, bool known);

// Object Iteration
typedef void(*GuardianCallback)(WowObject* unit, uint8_t* desc, void* ctx);
void ForEachPlayerGuardian(uint64_t playerGuid, GuardianCallback cb, void* ctx);

bool PatternScan(DWORD start, DWORD size, const char* pattern, const char* mask, DWORD* result);
DWORD FindDescriptorWriteHook(DWORD base);
DWORD FindUpdateDisplayInfoHook(DWORD base);

void ScanOffsets();
bool IsInWorld();
bool IsInGlue();
uint64_t GetSelectedCharacterGuid();
// DBC Reader for creature display info
struct CreatureDisplayEntry {
    uint32_t displayID;
    uint32_t modelID;
    float    modelScale;
    char     texture1[128];
    char     texture2[128];
    char     texture3[128];
};

struct CreatureModelEntry {
    uint32_t modelID;
    char     modelPath[256];
};

bool LookupCreatureDisplay(uint32_t displayID, CreatureDisplayEntry* out);
bool LookupCreatureModel(uint32_t modelID, CreatureModelEntry* out);

void RegisterCustomLuaFunctions();
extern bool g_luaFunctionsRegistered;

bool GetDllDirectory(char* buffer, size_t size);
bool CreateDllSubdirectory(const char* name);
void GetSessionLogPath(char* buffer, size_t size);
void CleanupOldLogs(int maxFilesToKeep);
void Log(const char* format, ...);
