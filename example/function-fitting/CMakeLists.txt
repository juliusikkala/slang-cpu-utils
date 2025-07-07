cmake_minimum_required(VERSION 3.20)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/../../cmake")

project(CmdlineCalculator LANGUAGES Slang)

add_subdirectory("${CMAKE_SOURCE_DIR}/../../lib" lib)

add_executable(function-fitting function-fitting.slang)
target_link_libraries(function-fitting PRIVATE scul)

