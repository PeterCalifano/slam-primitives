include_guard(GLOBAL)
include(CMakeParseArguments)

function(handle_tbb)
    set(oneValueArgs TARGET)
    cmake_parse_arguments(HTBB "" "${oneValueArgs}" "" ${ARGN})

    if(NOT HTBB_TARGET)
        set(HTBB_TARGET tbb_compile_interface)
    endif()

    if(NOT TARGET ${HTBB_TARGET})
        add_library(${HTBB_TARGET} INTERFACE)
    endif()

    if(NOT ENABLE_TBB)
        set(TBB_ENABLED OFF PARENT_SCOPE)
        return()
    endif()

    find_package(TBB REQUIRED COMPONENTS tbb)

    target_link_libraries(${HTBB_TARGET} INTERFACE TBB::tbb)
    target_compile_definitions(${HTBB_TARGET} INTERFACE __TBB_ENABLED__=1)

    set(TBB_ENABLED ON PARENT_SCOPE)
endfunction()
