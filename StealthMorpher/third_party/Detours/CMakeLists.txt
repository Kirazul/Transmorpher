project(Detours)

add_library(
    ${PROJECT_NAME} STATIC
        creatwth.cpp
        detours.cpp
        detours.h
        detver.h
        disasm.cpp
        disolx86.cpp
        image.cpp
        modules.cpp
        uimports.cpp
)
set_property(SOURCE uimports.cpp APPEND PROPERTY HEADER_FILE_ONLY true)

target_include_directories(${PROJECT_NAME} PUBLIC
    "${CMAKE_SOURCE_DIR}/third_party"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_compile_options(
    ${PROJECT_NAME} PRIVATE
        /we4777
        /we4800
        /D_X86_
)
