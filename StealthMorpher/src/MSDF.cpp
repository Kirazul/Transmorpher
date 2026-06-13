#include "MSDF.h"
#include "font_exact/MSDF.cpp"

bool MSDF::IsInitialized() {
    return INITIALIZED;
}

void MSDF::shutdown() {
    s_prefetchPayload.clear();
    MSDFFont::Shutdown();

    if (g_msdfFreetype) {
        msdfgen::deinitializeFreetype(g_msdfFreetype);
        g_msdfFreetype = nullptr;
    }

    if (g_realFtLibrary) {
        FT_Done_FreeType(g_realFtLibrary);
        g_realFtLibrary = nullptr;
    }

    IS_CJK = false;
    INITIALIZED = false;
}
