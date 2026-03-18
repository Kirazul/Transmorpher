#pragma once
#include <windows.h>
#include <cstdio>

static void Log(const char* fmt, ...) {
    static bool s_logInitialized = false;
    const char* logPath = "Logs\\Transmorpher.log";
    
    if (!s_logInitialized) {
        CreateDirectoryA("Logs", NULL);
    }
    
    FILE* f;
    if (fopen_s(&f, logPath, s_logInitialized ? "a" : "w") == 0) {
        s_logInitialized = true;
        // Truncate log if it gets too large (>2MB)
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        if (size > 2 * 1024 * 1024) {
            fclose(f);
            // Reopen in write mode to truncate
            if (fopen_s(&f, logPath, "w") != 0) return;
            SYSTEMTIME st;
            GetLocalTime(&st);
            fprintf(f, "[%02d:%02d:%02d.%03d] Log truncated (was %ld bytes)\n", st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, size);
        }
        SYSTEMTIME st;
        GetLocalTime(&st);
        fprintf(f, "[%02d:%02d:%02d.%03d] ", st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
        va_list args;
        va_start(args, fmt);
        vfprintf(f, fmt, args);
        va_end(args);
        fprintf(f, "\n");
        fclose(f);
    }
}
