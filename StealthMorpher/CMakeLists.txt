cmake_minimum_required(VERSION 3.15)
project(StealthMorpher LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")

add_compile_definitions(
    WIN32_LEAN_AND_MEAN
    _CRT_SECURE_NO_WARNINGS
    UNICODE
    _UNICODE
)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(FT_DISABLE_ZLIB ON CACHE BOOL "" FORCE)
set(FT_DISABLE_PNG ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BZIP2 ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BROTLI ON CACHE BOOL "" FORCE)
set(FT_DISABLE_HARFBUZZ ON CACHE BOOL "" FORCE)

add_subdirectory("${CMAKE_SOURCE_DIR}/third_party/Detours" "${CMAKE_BINARY_DIR}/third_party/Detours")
add_subdirectory("${CMAKE_SOURCE_DIR}/third_party/freetype-2.14.1" "${CMAKE_BINARY_DIR}/third_party/freetype-2.14.1")
if(NOT TARGET Freetype::Freetype)
    add_library(Freetype::Freetype ALIAS freetype)
endif()
add_subdirectory("${CMAKE_SOURCE_DIR}/third_party/msdfgen" "${CMAKE_BINARY_DIR}/third_party/msdfgen")

file(GLOB FONT_EXACT_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/src/font_exact/*.cpp"
)
list(REMOVE_ITEM FONT_EXACT_SOURCES "${CMAKE_SOURCE_DIR}/src/font_exact/MSDF.cpp")

# Output directory for the DLL
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/Release)

# Source files with absolute paths to avoid space issues
set(SOURCES
    "${CMAKE_SOURCE_DIR}/src/dllmain.cpp"
    "${CMAKE_SOURCE_DIR}/src/Utils.cpp"
    "${CMAKE_SOURCE_DIR}/src/Proxy.cpp"
    "${CMAKE_SOURCE_DIR}/src/Hooks.cpp"
    "${CMAKE_SOURCE_DIR}/src/Morpher.cpp"
    "${CMAKE_SOURCE_DIR}/src/SpellMorph.cpp"
    "${CMAKE_SOURCE_DIR}/src/D3DHooks.cpp"
    "${CMAKE_SOURCE_DIR}/src/RenderOverrides.cpp"
    "${CMAKE_SOURCE_DIR}/src/RenderEnables.cpp"
    "${CMAKE_SOURCE_DIR}/src/MSDF.cpp"
    ${FONT_EXACT_SOURCES}
)

# Create the DLL
add_library(dinput8 SHARED ${SOURCES} "${CMAKE_SOURCE_DIR}/src/dinput8_exports.def")

target_include_directories(dinput8 PRIVATE
    "${CMAKE_SOURCE_DIR}/src"
    "${CMAKE_SOURCE_DIR}/third_party"
    "${CMAKE_SOURCE_DIR}/third_party/unordered_dense/unordered_dense-4.8.1/include"
)

# Link against required libraries
target_link_libraries(dinput8
    psapi
    d3d9
    Detours
    Freetype::Freetype
    msdfgen-core
    msdfgen-ext
)

# Set output name to dinput8.dll
set_target_properties(dinput8 PROPERTIES
    OUTPUT_NAME "dinput8"
    PREFIX ""
    SUFFIX ".dll"
)

# Compiler flags for 32-bit build
if(MSVC)
    # MSVC specific flags
    target_compile_options(dinput8 PRIVATE /W3)
    set_target_properties(dinput8 PROPERTIES
        LINK_FLAGS "/DEF:\"${CMAKE_SOURCE_DIR}/src/dinput8_exports.def\""
    )
else()
    # MinGW/GCC flags
    target_compile_options(dinput8 PRIVATE -m32 -Wall)
    set_target_properties(dinput8 PROPERTIES
        LINK_FLAGS "-m32 -static-libgcc -static-libstdc++ -Wl,--enable-stdcall-fixup"
    )
endif()
