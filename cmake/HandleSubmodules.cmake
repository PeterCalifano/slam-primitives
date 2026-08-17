# CMake configuration to handle submodule inclusion and automatic build
include_guard(GLOBAL)

function(handle_submodules)
    # Root is where the function is called from
    set(_lib_search_path "${CMAKE_CURRENT_SOURCE_DIR}/lib")

    if (EXISTS "${_lib_search_path}")
        file(GLOB _submodule_dirs LIST_DIRECTORIES true "${_lib_search_path}/*")
        foreach(_submodule_dir IN LISTS _submodule_dirs)
            if (IS_DIRECTORY "${_submodule_dir}")
            get_filename_component(_submodule_name "${_submodule_dir}" NAME)

            # Ensure cmake CMP0077 policy
            set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)

            if (NOT _submodule_name STREQUAL "header_only" AND
                NOT _submodule_name STREQUAL "Catch2" AND
                NOT _submodule_name STREQUAL "wrap")
                if (EXISTS "${_submodule_dir}/CMakeLists.txt")
                    add_subdirectory("${_submodule_dir}" EXCLUDE_FROM_ALL)
                endif()
            endif()
            endif()
        endforeach()
    endif()
endfunction()
