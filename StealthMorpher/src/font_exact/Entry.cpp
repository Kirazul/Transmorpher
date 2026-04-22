#include "D3D.h"
#include "Hooks.h"
#include "MSDF.h"
#include "../Logger.h"

#include <Windows.h>
#include <cstdio>
#include <cstring>
#include <string>
#include "../../third_party/Detours/detours.h"

namespace {
    bool LoadPersistedMSDFEnabled() {
        char dllPath[MAX_PATH] = {0};
        if (!GetModuleFileNameA(GetModuleHandleA("dinput8.dll"), dllPath, MAX_PATH)) {
            Log("[MSDF] Could not resolve dinput8.dll path, defaulting to disabled");
            return false;
        }

        char* lastSlash = strrchr(dllPath, '\\');
        if (!lastSlash) {
            Log("[MSDF] Could not resolve DLL directory, defaulting to disabled");
            return false;
        }
        *lastSlash = '\0';

        char modePath[MAX_PATH] = {0};
        sprintf_s(modePath, sizeof(modePath), "%s\\state\\msdf_mode.txt", dllPath);

        FILE* file = nullptr;
        if (fopen_s(&file, modePath, "rb") != 0 || !file) {
            Log("[MSDF] Mode file missing, defaulting to disabled: %s", modePath);
            return false;
        }

        const int value = fgetc(file);
        fclose(file);
        const bool enabled = value == '1';
        Log("[MSDF] Loaded persisted mode=%d from %s", enabled ? 1 : 0, modePath);
        return enabled;
    }

    bool OnAttach() {
        if (!LoadPersistedMSDFEnabled()) {
            Log("[MSDF] Startup skipped because persisted mode is disabled");
            return false;
        }

        Hooks::initialize();

        LONG status = DetourTransactionBegin();
        if (status != NO_ERROR) {
            return false;
        }

        status = DetourUpdateThread(GetCurrentThread());
        if (status != NO_ERROR) {
            DetourTransactionAbort();
            return false;
        }

        D3D::initialize();
        MSDF::initialize();

        status = DetourTransactionCommit();
        if (status != NO_ERROR) {
            Log("[MSDF] Startup initialization failed during commit (error=%ld)", status);
            return false;
        }

        Log("[MSDF] Startup initialization committed");

        const std::string locale = MSDF::GetGameLocale();
        const bool isCjk = (locale == "zhCN" || locale == "zhTW" || locale == "koKR");
        if (!isCjk) {
            Log("[MSDF] Late bootstrap activation applied after commit");
        }

        return true;
    }
}

bool FontExact_OnAttach() {
    return OnAttach();
}
