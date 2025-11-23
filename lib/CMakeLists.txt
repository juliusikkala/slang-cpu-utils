cmake_minimum_required(VERSION 3.20)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/../cmake")

project(SCUL LANGUAGES Slang C)

find_package(Threads REQUIRED)

add_custom_command(
    OUTPUT ctypes.slang
    DEPENDS 
        ${CMAKE_CURRENT_SOURCE_DIR}/ctypes.h
    COMMAND slang-bindgen
        ${CMAKE_CURRENT_SOURCE_DIR}/ctypes.h
        --output ctypes.slang
        --namespace C
    COMMENT "Generating ctypes.slang"
)

add_custom_command(
    OUTPUT crt.slang
    DEPENDS 
        ${CMAKE_CURRENT_SOURCE_DIR}/ctypes.h
        ${CMAKE_CURRENT_SOURCE_DIR}/crt.h
    COMMAND slang-bindgen
        ${CMAKE_CURRENT_SOURCE_DIR}/crt.h
        --import ctypes
        --imported ${CMAKE_CURRENT_SOURCE_DIR}/ctypes.h
        --output crt.slang
        --namespace C
    COMMENT "Generating crt.slang"
)

add_custom_target(bindgen DEPENDS ctypes.slang crt.slang)

add_slang_library(scul
    ctypes.slang
    crt.slang
    memory.slang
    panic.slang
)

target_include_directories(scul PUBLIC ${CMAKE_CURRENT_BINARY_DIR})

target_link_libraries(scul Threads::Threads)
add_dependencies(scul bindgen)
