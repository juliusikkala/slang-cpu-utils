cmake_minimum_required(VERSION 3.20)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/../cmake")

project(SCUL LANGUAGES Slang C)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Threads REQUIRED)

add_custom_command(
    OUTPUT crt.slang
    DEPENDS 
        ${CMAKE_CURRENT_SOURCE_DIR}/crt.h
    COMMAND slang-bindgen
        ${CMAKE_CURRENT_SOURCE_DIR}/crt.h
        --output crt.slang
        --export-symbols exit,malloc,realloc,free,memcpy,memset,strcmp,fopen,fclose,fread,fgetc,fwrite,ftell,fseek,FILE,stdout,stderr,stdin,time,difftime,clock,aligned_alloc,_aligned_alloc,_aligned_realloc,_aligned_free,timespec,thrd_sleep,timespec_get,thrd_t,thrd_create,thrd_join,mtx_t,mtx_init,mtx_lock,mtx_trylock,mtx_unlock,mtx_destroy,mtx_plain,mtx_recursive,mtx_timed,strlen
        --namespace C
    COMMENT "Generating crt.slang"
)

add_custom_target(bindgen DEPENDS crt.slang)

add_slang_library(scul
    array.slang
    binarystream.slang
    color.slang
    crt.slang
    csv.slang
    drop.slang
    equal.slang
    geometry.slang
    hash.slang
    hashmap.slang
    hashset.slang
    image.slang
    io.slang
    list.slang
    memory.slang
    optimization.slang
    panic.slang
    random.slang
    serialization.slang
    sort.slang
    span.slang
    string.slang
    thread.slang
    time.slang
)

target_include_directories(scul PUBLIC ${CMAKE_CURRENT_BINARY_DIR})

target_link_libraries(scul Threads::Threads)
add_dependencies(scul bindgen)
