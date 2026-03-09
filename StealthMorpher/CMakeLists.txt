cmake_minimum_required(VERSION 3.10)
project(StealthMorpher)

# Set C++ standard
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Output directory for the DLL
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/Release)

# Source files with absolute paths to avoid space issues
set(SOURCES
    "${CMAKE_SOURCE_DIR}/src/dllmain.cpp"
    "${CMAKE_SOURCE_DIR}/src/forwarders.cpp"
)

# Create the DLL
add_library(dinput8 SHARED ${SOURCES} "${CMAKE_SOURCE_DIR}/src/dinput8_exports.def")

# Link against required libraries
target_link_libraries(dinput8 psapi)

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
