cmake_minimum_required(VERSION 3.20)

project(SlangBindgen LANGUAGES C CXX)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(LLVM 21.1 REQUIRED CONFIG)
find_package(Clang REQUIRED CONFIG)

get_target_property(CLANG_PATH clang LOCATION)

if(LLVM_LINK_LLVM_DYLIB)
    set(LLVM_LINK_TYPE USE_SHARED)
endif()

function(clang_target_from_libs target_name)
    set(clang_libs ${ARGN})
    add_library(${target_name} INTERFACE)
    # Check if we have the individual modules or not.
    if(TARGET clangBasic)
        target_link_libraries(${target_name} INTERFACE ${clang_libs})
    else()
        # If not, we can still link to the catch-all clang-cpp.
        target_link_libraries(${target_name} INTERFACE clang-cpp)
    endif()
    target_include_directories(
        ${target_name}
        SYSTEM
        INTERFACE ${CLANG_INCLUDE_DIRS}
    )
    target_compile_definitions(${target_name} INTERFACE ${CLANG_DEFINITIONS})
endfunction()

find_package(Threads REQUIRED)

add_executable(slang-bindgen slang-bindgen.cpp)

clang_target_from_libs(
    clang-dep
    clangBasic
    clangCodeGen
    clangDriver
    clangLex
    clangFrontend
    clangFrontendTool
)
llvm_config(slang-bindgen ${LLVM_LINK_TYPE} ${LLVM_TARGETS_TO_BUILD} core support mc mcparser)

target_link_libraries(slang-bindgen PRIVATE clang-dep)
target_compile_definitions(slang-bindgen PRIVATE BINDGEN_PATH_TO_CLANG=\"${CLANG_PATH}\")

set_property(TARGET slang-bindgen PROPERTY C_STANDARD 11)
set_property(TARGET slang-bindgen PROPERTY CXX_STANDARD 17)
set_property(TARGET slang-bindgen PROPERTY CXX_STANDARD_REQUIRED ON)
set_property(TARGET slang-bindgen PROPERTY CXX_EXTENSIONS OFF)
