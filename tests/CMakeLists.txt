include(CTest)

function(test name)
    add_executable("${name}" "${name}.slang" "test.slang")
    target_link_libraries("${name}" PRIVATE scul)
    add_test(NAME "${name}"
        COMMAND "${name}"
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )
endfunction()

test(array_test)
test(drop_test)
test(hash_test)
test(hashmap_test)
test(hashset_test)
test(io_test)
test(list_test)
test(memory_test)
test(random_test)
test(sort_test)
test(span_test)
test(string_test)
#test(thread_test)
#test(time_test)
