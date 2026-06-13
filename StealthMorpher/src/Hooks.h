#pragma once
#include <windows.h>
#include <cstdint>

extern float g_timeOfDay;
extern uint32_t g_morphTitle;
extern bool g_timeHookInstalled;
extern uint32_t g_origTitle;

extern DWORD TIME_HOOK_ADDR;
extern DWORD TIME_VAR_ADDR;

bool InstallTimeHook();
void UninstallTimeHook();

bool InstallMountHook();
void UninstallMountHook();

bool InstallUpdateDisplayInfoHook();
void UninstallUpdateDisplayInfoHook();

extern volatile bool g_mountHookBypass;

extern "C" void MountDisplayHook();
extern "C" void UpdateDisplayInfoHook();


