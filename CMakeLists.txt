cmake_minimum_required(VERSION 3.20)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

project(SlangCpuUtils LANGUAGES Slang)
option(SCL_BUILD_TESTS "Build SCL tests" ON)

add_subdirectory(lib)
if(SCL_BUILD_TESTS)
    add_subdirectory(tests)
endif()
