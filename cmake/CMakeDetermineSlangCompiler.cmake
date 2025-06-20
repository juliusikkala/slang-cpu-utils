if(NOT CMAKE_Slang_COMPILER)
    set(Slang_BIN_PATH
        "$ENV{VULKAN_SDK}/bin"
        /usr/bin
        /usr/local/bin
        )

    if(CMAKE_Slang_COMPILER_INIT)
        set(CMAKE_Slang_COMPILER ${CMAKE_Slang_COMPILER_INIT} CACHE PATH "Slang Compiler")
    else()
        find_program(CMAKE_Slang_COMPILER
            NAMES slangc
            PATHS ${Slang_BIN_PATH}
        )
    endif()
endif()

mark_as_advanced(CMAKE_Slang_COMPILER)
set(CMAKE_Slang_COMPILER_ENV_VAR "SLANG_COMPILER")
set(CMAKE_Slang_SOURCE_FILE_EXTENSIONS slang)
#set(CMAKE_Slang_OUTPUT_EXTENSION slang-module)
configure_file(${CMAKE_CURRENT_LIST_DIR}/CMakeSlangCompiler.cmake.in
    ${CMAKE_PLATFORM_INFO_DIR}/CMakeSlangCompiler.cmake @ONLY)
