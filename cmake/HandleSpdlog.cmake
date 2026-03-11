include_guard(GLOBAL)
include(CMakeParseArguments)

function(handle_spdlog)
    set(oneValueArgs TARGET)
    cmake_parse_arguments(HSPDLOG "" "${oneValueArgs}" "" ${ARGN})

    if(NOT HSPDLOG_TARGET)
        set(HSPDLOG_TARGET spdlog_compile_interface)
    endif()

    if(NOT TARGET ${HSPDLOG_TARGET})
        add_library(${HSPDLOG_TARGET} INTERFACE)
    endif()

    set(_spdlog_local_dir "${PROJECT_SOURCE_DIR}/lib/spdlog")

    set(_spdlog_enabled OFF)
    set(_resolved_spdlog_target "")
    set(_spdlog_external_package OFF)

    if(ENABLE_SPDLOG)
        if(TARGET spdlog::spdlog_header_only OR TARGET spdlog::spdlog)
            set(_spdlog_enabled ON)
            set(_spdlog_external_package ON)
        else()
            find_package(spdlog CONFIG QUIET)
            if(spdlog_FOUND)
                set(_spdlog_enabled ON)
                set(_spdlog_external_package ON)
            endif()
        endif()

        if(NOT _spdlog_enabled AND EXISTS "${_spdlog_local_dir}/CMakeLists.txt")
            message(STATUS "spdlog found in lib/. Adding ${_spdlog_local_dir} to the build...")
            add_subdirectory("${_spdlog_local_dir}" "${CMAKE_BINARY_DIR}/_deps/spdlog-build" EXCLUDE_FROM_ALL)
            if(TARGET spdlog::spdlog_header_only OR TARGET spdlog::spdlog)
                set(_spdlog_enabled ON)
            endif()
        endif()

        if(NOT _spdlog_enabled AND ENABLE_FETCH_SPDLOG)
            message(STATUS "spdlog not found. Will try to fetch it into lib/ ...")
            find_package(Git QUIET)

            if(NOT Git_FOUND)
                message(WARNING "Git not found; cannot fetch spdlog. Logging utilities will be disabled.")
            elseif(EXISTS "${_spdlog_local_dir}")
                message(WARNING "Local spdlog directory exists but is not usable: ${_spdlog_local_dir}. Logging utilities will be disabled.")
            else()
                execute_process(
                    COMMAND "${GIT_EXECUTABLE}" ls-remote https://github.com/gabime/spdlog.git
                    RESULT_VARIABLE _git_result
                    OUTPUT_QUIET
                    ERROR_QUIET
                    TIMEOUT 10)

                if(_git_result EQUAL 0)
                    execute_process(
                        COMMAND "${GIT_EXECUTABLE}" clone --depth 1 --branch v1.14.1 https://github.com/gabime/spdlog.git "${_spdlog_local_dir}"
                        RESULT_VARIABLE _git_clone_result
                        OUTPUT_QUIET
                        ERROR_QUIET
                        TIMEOUT 300)

                    if(_git_clone_result EQUAL 0 AND EXISTS "${_spdlog_local_dir}/CMakeLists.txt")
                        add_subdirectory("${_spdlog_local_dir}" "${CMAKE_BINARY_DIR}/_deps/spdlog-build" EXCLUDE_FROM_ALL)
                        if(TARGET spdlog::spdlog_header_only OR TARGET spdlog::spdlog)
                            set(_spdlog_enabled ON)
                        endif()
                    else()
                        message(WARNING "Failed to clone spdlog into lib/. Logging utilities will be disabled.")
                    endif()
                else()
                    message(WARNING "Cannot reach GitHub (no network or blocked). Logging utilities will be disabled.")
                endif()
            endif()
        elseif(NOT _spdlog_enabled AND NOT ENABLE_FETCH_SPDLOG)
            message(STATUS "spdlog not found and ENABLE_FETCH_SPDLOG=OFF. Logging utilities will be disabled.")
        endif()
    else()
        message(STATUS "spdlog support disabled by configuration (ENABLE_SPDLOG=OFF).")
    endif()

    if(_spdlog_enabled)
        if(NOT _spdlog_external_package AND TARGET spdlog_header_only)
            set(_resolved_spdlog_target spdlog_header_only)
        elseif(NOT _spdlog_external_package AND TARGET spdlog)
            set(_resolved_spdlog_target spdlog)
        elseif(TARGET spdlog::spdlog_header_only)
            set(_resolved_spdlog_target spdlog::spdlog_header_only)
        elseif(TARGET spdlog::spdlog)
            set(_resolved_spdlog_target spdlog::spdlog)
        else()
            message(WARNING "spdlog was detected but no supported target was found. Logging utilities will be disabled.")
            set(_spdlog_enabled OFF)
        endif()
    endif()

    if(_spdlog_enabled)
        target_link_libraries(${HSPDLOG_TARGET} INTERFACE ${_resolved_spdlog_target})
        message(STATUS "spdlog enabled via target: ${_resolved_spdlog_target}")
    endif()

    set(SPDLOG_ENABLED ${_spdlog_enabled} PARENT_SCOPE)
    set(SPDLOG_LINK_TARGET ${_resolved_spdlog_target} PARENT_SCOPE)
    set(SPDLOG_EXTERNAL_PACKAGE ${_spdlog_external_package} PARENT_SCOPE)
endfunction()
