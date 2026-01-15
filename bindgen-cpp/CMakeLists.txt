# This snippet just exists to help setting up Bindgen in a CMake project.

find_package(Python3 COMPONENTS Interpreter REQUIRED)
execute_process(COMMAND ${Python3_EXECUTABLE} -m venv ${CMAKE_CURRENT_LIST_DIR}/venv)

set(ENV{VIRTUAL_ENV} ${CMAKE_CURRENT_LIST_DIR}/venv)
set(Python3_FIND_VIRTUALENV FIRST)
unset(Python3_EXECUTABLE)
find_package(Python3 COMPONENTS Interpreter)

execute_process(COMMAND ${Python3_EXECUTABLE} -m pip install -r ${CMAKE_CURRENT_LIST_DIR}/requirements.txt)

set(SLANG_BINDGEN
    "${Python3_EXECUTABLE}"
    "${CMAKE_CURRENT_SOURCE_DIR}/bindgen.py"
    PARENT_SCOPE)
