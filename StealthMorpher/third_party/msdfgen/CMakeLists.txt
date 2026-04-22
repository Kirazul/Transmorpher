project(msdfgen LANGUAGES CXX C)

file(GLOB MSDFGEN_CORE_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/core/*.cpp"
)

add_library(msdfgen-core STATIC ${MSDFGEN_CORE_SOURCES})
add_library(msdfgen::msdfgen-core ALIAS msdfgen-core)

target_include_directories(msdfgen-core PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_compile_definitions(msdfgen-core PUBLIC
    MSDFGEN_PUBLIC=
    MSDFGEN_EXT_PUBLIC=
    MSDFGEN_USE_CPP11
    MSDFGEN_USE_SKIA
)

target_link_libraries(msdfgen-core PUBLIC Freetype::Freetype)

add_library(msdfgen-ext STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/ext/resolve-shape-geometry.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/ext/import-font.cpp"
)
add_library(msdfgen::msdfgen-ext ALIAS msdfgen-ext)

target_include_directories(msdfgen-ext PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_SOURCE_DIR}/third_party/skia"
    "${CMAKE_SOURCE_DIR}/third_party/skia/include"
)

target_compile_definitions(msdfgen-ext PUBLIC
    MSDFGEN_PUBLIC=
    MSDFGEN_EXT_PUBLIC=
    MSDFGEN_USE_CPP11
    MSDFGEN_USE_SKIA
)

target_link_libraries(msdfgen-ext PUBLIC
    msdfgen-core
    Freetype::Freetype
    "${CMAKE_SOURCE_DIR}/third_party/skia/skia.lib"
)
