cmake_minimum_required(VERSION 3.10)
project(StealthMorpher)

# Target 32-bit (x86) since 3.3.5a is 32-bit
set(CMAKE_GENERATOR_PLATFORM Win32)
set(CMAKE_CXX_STANDARD 17)

# unified proxy + morpher
add_library(dinput8 SHARED src/dllmain.cpp src/forwarders.cpp src/dinput8_exports.def)
target_link_libraries(dinput8 d3d9)
set_target_properties(dinput8 PROPERTIES PREFIX "")
