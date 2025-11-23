cmake_minimum_required(VERSION 3.20)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/../cmake")

project(SCUL LANGUAGES Slang C)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

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
    OUTPUT cconstants.slang
    DEPENDS 
        ${CMAKE_CURRENT_SOURCE_DIR}/cconstants.h
    COMMAND slang-bindgen
        ${CMAKE_CURRENT_SOURCE_DIR}/cconstants.h
        --output cconstants.slang
        --namespace C
    COMMENT "Generating cconstants.slang"
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

add_custom_target(bindgen DEPENDS ctypes.slang crt.slang cconstants.slang)

add_slang_library(scul
    array.slang
    crt.slang
    ctypes.slang
    cconstants.slang
    drop.slang
    equal.slang
    hash.slang
    hashmap.slang
    hashset.slang
    io.slang
    list.slang
    memory.slang
    panic.slang
    random.slang
    sort.slang
    span.slang
    string.slang
    #thread.slang
    #time.slang
)

target_include_directories(scul PUBLIC ${CMAKE_CURRENT_BINARY_DIR})

target_link_libraries(scul Threads::Threads)
add_dependencies(scul bindgen)
