if (WIN32)
    set(CMAKE_Slang_FLAGS_INIT "-DSLANG_PLATFORM_WIN32")
elseif(UNIX)
    set(CMAKE_Slang_FLAGS_INIT "-DSLANG_PLATFORM_UNIX")
endif()

# TODO: What if the downstream compiler is MSVC? Handle that case.
set(CMAKE_Slang_FLAGS_DEBUG_INIT "-g3 -Xgenericcpp... -g -X.")
set(CMAKE_Slang_FLAGS_RELEASE_INIT "-O3 -g0 -DNDEBUG -Xgenericcpp... -O2 -DNDEBUG -X.")
set(CMAKE_Slang_FLAGS_RELWITHDEBINFO_INIT "-O2 -g2 -Xgenericcpp... -O2 -g -X.")

set(CMAKE_INCLUDE_FLAG_Slang "-I")

set(CMAKE_SHARED_MODULE_PREFIX_Slang "")
set(CMAKE_SHARED_MODULE_SUFFIX_Slang ".slang-module")
set(CMAKE_Slang_CREATE_SHARED_MODULE "<CMAKE_Slang_COMPILER> <OBJECTS> -o <TARGET>")

cmake_initialize_per_config_variable(CMAKE_Slang_FLAGS "Flags used by the Slang compiler")

set(CMAKE_Slang_DEPFILE_FORMAT gcc)
set(CMAKE_Slang_DEPENDS_USE_COMPILER TRUE)
set(CMAKE_DEPFILE_FLAGS_Slang "-depfile <DEP_FILE>")

set(CMAKE_Slang_COMPILE_OBJECT
    "<CMAKE_Slang_COMPILER> <DEFINES> <INCLUDES> <FLAGS> <SOURCE> -o <OBJECT>"
)

set(CMAKE_Slang_OUTPUT_EXTENSION -module)

# Build a executable 
if (WIN32)
    set(CMAKE_Slang_LINK_EXECUTABLE 
        "<CMAKE_Slang_COMPILER> -target executable <CMAKE_Slang_LINK_FLAGS> -Xgenericcpp... <LINK_FLAGS> <LINK_LIBRARIES> -X. -o <TARGET> <OBJECTS>"
    )
elseif(UNIX)
    set(CMAKE_Slang_LINK_EXECUTABLE 
        "<CMAKE_Slang_COMPILER> -target executable <CMAKE_Slang_LINK_FLAGS> -Xgenericcpp... -w <LINK_FLAGS> <LINK_LIBRARIES> -X. -o <TARGET> <OBJECTS>"
    )
endif()

set(CMAKE_Slang_LINKER_PREFERENCE Slang) 
set(CMAKE_Slang_INFORMATION_LOADED 1)

function(add_slang_library target-name)
    add_library(${target-name} OBJECT ${ARGN})
    
    # This is something we _probably_ shouldn't be doing, but it works... 
    set(MODULE_PATH ${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${target-name}.dir)

    target_include_directories(${target-name} INTERFACE ${MODULE_PATH})
    # This one's a bit funny. Typical link flags would be addressed to the 
    # downstream C++ compiler. However, we escape out with `-X.` to pass flags
    # directly to Slang for this one to work.
    target_link_options(${target-name} INTERFACE -X. -I${MODULE_PATH} -Xgenericcpp...)
endfunction()

# TODO Figure out a clean way to allow passing flags to shader Slang only!
#function(add_shader target)
#    if(NOT TARGET shaders)
#        # This custom target can be used for shader hot-reloading functionality.
#        add_custom_target(shaders)
#    endif()
#    foreach(source ${ARGN})
#        get_filename_component(shader_bin_name ${source} NAME)
#        string(REPLACE "\." "_" shader_bin_name ${shader_bin_name})
#        string(CONCAT binary ${source} ".spv")
#
#        list(TRANSFORM SHADER_INCLUDE_DIRS PREPEND "-I" OUTPUT_VARIABLE SHADER_INCLUDE_ARGS)
#
#        add_custom_command(
#            OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${binary}
#            COMMAND slangc -fvk-use-gl-layout -fvk-use-entrypoint-name -matrix-layout-row-major -target spirv -O2 -g ${CMAKE_CURRENT_SOURCE_DIR}/${source} -o ${CMAKE_CURRENT_BINARY_DIR}/${binary} ${SHADER_INCLUDE_ARGS}
#            COMMAND_EXPAND_LISTS
#            MAIN_DEPENDENCY ${CMAKE_CURRENT_SOURCE_DIR}/${source}
#            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${source}
#            IMPLICIT_DEPENDS Slang ${CMAKE_CURRENT_SOURCE_DIR}/${source}
#            VERBATIM
#        )
#        add_custom_target(${binary}_target DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${binary})
#        add_dependencies(${target} ${binary}_target)
#        add_dependencies(shaders ${binary}_target)
#    endforeach()
#endfunction()
