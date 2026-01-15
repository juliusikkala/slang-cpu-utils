cmake_minimum_required(VERSION 3.20)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(SlangCpuUtils LANGUAGES Slang C)
option(SCUL_BUILD_TESTS "Build SCUL tests" ON)

add_subdirectory(bindgen-llvm)

add_subdirectory(lib)
if(SCUL_BUILD_TESTS)
    add_subdirectory(tests)
endif()
