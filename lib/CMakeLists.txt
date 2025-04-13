cmake_minimum_required(VERSION 3.20)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/../cmake")

project(SCL LANGUAGES Slang)

add_slang_library(scl
    platform.slang
    panic.slang
    drop.slang
    memory.slang
    thread.slang
    hash.slang
    sort.slang
    span.slang
    array.slang
    list.slang
    hashset.slang
    hashmap.slang
)
