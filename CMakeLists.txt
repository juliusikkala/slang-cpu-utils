cmake_minimum_required(VERSION 3.20)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

project(SlangCpuUtils LANGUAGES Slang)
option(SCUL_BUILD_TESTS "Build SCUL tests" ON)
option(SCUL_BUILD_BINDGEN "Build binding generator" ON)

add_subdirectory(lib)
if(SCUL_BUILD_TESTS)
    add_subdirectory(tests)
endif()
if(SCUL_BUILD_BINDGEN)
    add_subdirectory(bindgen-llvm)
endif()
