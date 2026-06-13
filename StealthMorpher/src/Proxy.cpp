#include "Proxy.h"
#include "Logger.h"
#include <cstdio>
#include <cstring>
#include <cctype>

extern "C" {
    FARPROC p_dinput8[5] = {0};
    __declspec(naked) void dinput8_DirectInput8Create() { __asm { jmp [p_dinput8 + 0] } }
    __declspec(naked) void dinput8_GetdfDIJoystick() { __asm { jmp [p_dinput8 + 4] } }
    __declspec(naked) void dinput8_GetdfDIKeyboard() { __asm { jmp [p_dinput8 + 8] } }
    __declspec(naked) void dinput8_GetdfDIMouse() { __asm { jmp [p_dinput8 + 12] } }
    __declspec(naked) void dinput8_GetdfDIMouse2() { __asm { jmp [p_dinput8 + 16] } }
}

extern "C" {
    FARPROC p_version[17] = {0};
    __declspec(naked) void version_GetFileVersionInfoA() { __asm { jmp [p_version + 0] } }
    __declspec(naked) void version_GetFileVersionInfoW() { __asm { jmp [p_version + 4] } }
    __declspec(naked) void version_GetFileVersionInfoSizeA() { __asm { jmp [p_version + 8] } }
    __declspec(naked) void version_GetFileVersionInfoSizeW() { __asm { jmp [p_version + 12] } }
    __declspec(naked) void version_VerQueryValueA() { __asm { jmp [p_version + 16] } }
    __declspec(naked) void version_VerQueryValueW() { __asm { jmp [p_version + 20] } }
}

extern "C" {
    FARPROC p_dsound[12] = {0};
    __declspec(naked) void dsound_DirectSoundCreate() { __asm { jmp [p_dsound + 0] } }
    __declspec(naked) void dsound_DirectSoundEnumerateA() { __asm { jmp [p_dsound + 4] } }
    __declspec(naked) void dsound_DirectSoundEnumerateW() { __asm { jmp [p_dsound + 8] } }
    __declspec(naked) void dsound_DllCanUnloadNow() { __asm { jmp [p_dsound + 12] } }
    __declspec(naked) void dsound_DllGetClassObject() { __asm { jmp [p_dsound + 16] } }
    __declspec(naked) void dsound_DirectSoundCaptureCreate() { __asm { jmp [p_dsound + 20] } }
    __declspec(naked) void dsound_DirectSoundCaptureEnumerateA() { __asm { jmp [p_dsound + 24] } }
    __declspec(naked) void dsound_DirectSoundCaptureEnumerateW() { __asm { jmp [p_dsound + 28] } }
    __declspec(naked) void dsound_GetDeviceID() { __asm { jmp [p_dsound + 32] } }
    __declspec(naked) void dsound_DirectSoundFullDuplexCreate() { __asm { jmp [p_dsound + 36] } }
    __declspec(naked) void dsound_DirectSoundCreate8() { __asm { jmp [p_dsound + 40] } }
    __declspec(naked) void dsound_DirectSoundCaptureCreate8() { __asm { jmp [p_dsound + 44] } }
}

extern HMODULE g_hThisModule;

void SetupProxy() {
    char sysDir[MAX_PATH];
    GetSystemDirectoryA(sysDir, MAX_PATH);
    
    char dllPath[MAX_PATH];
    if (!g_hThisModule) {
        // Fallback if DllMain hasn't run yet or failed to save module handle
        GetModuleFileNameA(NULL, dllPath, MAX_PATH);
    } else {
        GetModuleFileNameA(g_hThisModule, dllPath, MAX_PATH);
    }
    
    char* fname = strrchr(dllPath, '\\');
    if (fname) fname++; else fname = dllPath;
    
    char lowerName[MAX_PATH];
    strcpy_s(lowerName, fname);
    for(int i=0; lowerName[i]; i++) lowerName[i] = tolower(lowerName[i]);
    
    Log("Proxy DLL loaded as: %s", lowerName);
    
    if (strstr(lowerName, "version.dll")) {
        strcat_s(sysDir, "\\version.dll");
        HMODULE hMod = LoadLibraryA(sysDir);
        if (hMod) {
            p_version[0] = GetProcAddress(hMod, "GetFileVersionInfoA");
            p_version[1] = GetProcAddress(hMod, "GetFileVersionInfoW");
            p_version[2] = GetProcAddress(hMod, "GetFileVersionInfoSizeA");
            p_version[3] = GetProcAddress(hMod, "GetFileVersionInfoSizeW");
            p_version[4] = GetProcAddress(hMod, "VerQueryValueA");
            p_version[5] = GetProcAddress(hMod, "VerQueryValueW");
            Log("Proxied version.dll");
        } else {
            Log("ERROR: Failed to load system version.dll from %s (err=%lu)", sysDir, GetLastError());
        }
    }
    else if (strstr(lowerName, "dsound.dll")) {
        strcat_s(sysDir, "\\dsound.dll");
        HMODULE hMod = LoadLibraryA(sysDir);
        if (hMod) {
            p_dsound[0] = GetProcAddress(hMod, "DirectSoundCreate");
            p_dsound[1] = GetProcAddress(hMod, "DirectSoundEnumerateA");
            p_dsound[2] = GetProcAddress(hMod, "DirectSoundEnumerateW");
            p_dsound[3] = GetProcAddress(hMod, "DllCanUnloadNow");
            p_dsound[4] = GetProcAddress(hMod, "DllGetClassObject");
            p_dsound[5] = GetProcAddress(hMod, "DirectSoundCaptureCreate");
            p_dsound[6] = GetProcAddress(hMod, "DirectSoundCaptureEnumerateA");
            p_dsound[7] = GetProcAddress(hMod, "DirectSoundCaptureEnumerateW");
            p_dsound[8] = GetProcAddress(hMod, "GetDeviceID");
            p_dsound[9] = GetProcAddress(hMod, "DirectSoundFullDuplexCreate");
            p_dsound[10] = GetProcAddress(hMod, "DirectSoundCreate8");
            p_dsound[11] = GetProcAddress(hMod, "DirectSoundCaptureCreate8");
            Log("Proxied dsound.dll");
        } else {
            Log("ERROR: Failed to load system dsound.dll from %s (err=%lu)", sysDir, GetLastError());
        }
    }
    else {
        // Default to dinput8.dll
        strcat_s(sysDir, "\\dinput8.dll");
        HMODULE hMod = LoadLibraryA(sysDir);
        if (hMod) {
            p_dinput8[0] = GetProcAddress(hMod, "DirectInput8Create");
            p_dinput8[1] = GetProcAddress(hMod, "GetdfDIJoystick");
            p_dinput8[2] = GetProcAddress(hMod, "GetdfDIKeyboard");
            p_dinput8[3] = GetProcAddress(hMod, "GetdfDIMouse");
            p_dinput8[4] = GetProcAddress(hMod, "GetdfDIMouse2");
            Log("Proxied dinput8.dll");
        } else {
            Log("ERROR: Failed to load system dinput8.dll from %s (err=%lu)", sysDir, GetLastError());
        }
    }
}
