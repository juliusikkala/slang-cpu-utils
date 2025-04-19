include(CTest)

function(test name)
    add_executable("${name}" "${name}.slang" "test.slang")
    target_link_libraries("${name}" PRIVATE scl)
    add_test(NAME "${name}"
        COMMAND "${name}"
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )
endfunction()

test(drop_test)
test(sort_test)
test(memory_test)
test(array_test)
test(hash_test)
test(thread_test)
test(time_test)
test(span_test)
