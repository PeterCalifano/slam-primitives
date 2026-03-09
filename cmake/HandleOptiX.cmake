# CMake configuration to handle OptiX SDK setup and linking or installation as library
include_guard(GLOBAL)
include(CMakeParseArguments)

# Option to auto-install OptiX SDK submodule
option(OPTIX_AUTO_INSTALL "Auto-install OptiX SDK submodule in lib/optix-sdk" ON)

# Default paths to OptiX SDK (empty)
set(OPTIX_ROOT "" CACHE PATH "OptiX SDK root (contains include/)")
set(SEARCH_ROOT_LIST_DIR "${CMAKE_CURRENT_LIST_DIR}" CACHE PATH "Root directory to search for OptiX SDK if OPTIX_ROOT not set, defined when defining function.")
set(OPTIX_SDK_REPO "git@github.com:PeterCalifano/optix-dev.git" CACHE STRING "OptiX SDK repo for auto-install")

function(handle_optix)

    # Add function arguments
    set(options)
    set(oneValueArgs TARGET CUDA_TARGET)
    cmake_parse_arguments(HOPT "${options}" "${oneValueArgs}" "" ${ARGN})

    # Define target for compile settings (OptiX specific, empty interface by default)
    if(NOT HOPT_TARGET)
        set(HOPT_TARGET optix_compile_interface)
    endif()
    if(NOT TARGET ${HOPT_TARGET})
        add_library(${HOPT_TARGET} INTERFACE)
    endif()

    set(OptiX_FOUND OFF PARENT_SCOPE)
    set(optix_LIBRARY "" PARENT_SCOPE)

    if(NOT ENABLE_OPTIX)
        return() # Return if OptiX not enabled
    endif()

    if(NOT ENABLE_CUDA)
        message(FATAL_ERROR "ENABLE_OPTIX requires ENABLE_CUDA=ON.")
    endif()

    set(_optix_root "")

    ### Select OptiX root directory
    # If USE_SYS_OPTIX_SDK is ON, use system-installed OptiX (from ENV{OPTIX_HOME}) OR if ENV{OPTIX_HOME} is defined, but USE_SYS_OPTIX_SDK false and OPTIX_ROOT is not defined, use that anyway
    # Else if OPTIX_ROOT is defined, use that
    # Else try default path relative to this file or auto-install from git submodule
    if(USE_SYS_OPTIX_SDK OR (DEFINED ENV{OPTIX_HOME} AND NOT OPTIX_ROOT))
        if(DEFINED ENV{OPTIX_HOME})
            set(_optix_root "$ENV{OPTIX_HOME}")
        else()
            message(FATAL_ERROR "USE_SYS_OPTIX_SDK is enabled but OPTIX_HOME is not defined.")
        endif()
    elseif(OPTIX_ROOT)
        set(_optix_root "${OPTIX_ROOT}")
    else()

        # First search for optix in lib/<any_folder_containing_optix>/include/optix.h
        set(_lib_optix_found OFF)
        set(_optix_lib_dir "${SEARCH_ROOT_LIST_DIR}/../lib")
        message(STATUS "Searching for OptiX SDK in subfolders of: ${_optix_lib_dir}")
        file(GLOB _lib_folders LIST_DIRECTORIES ON "${_optix_lib_dir}/*")

        foreach(_folder IN LISTS _lib_folders)
            if(EXISTS "${_folder}/include/optix.h")
                set(_lib_optix_found ON)
                set(_lib_optix_root "${_folder}")
                break()
            endif()
        endforeach()

        # If not found in lib/ or auto-install disabled, try to use auto-install or fail
        if (NOT OPTIX_AUTO_INSTALL OR _lib_optix_found)

            if (NOT OPTIX_AUTO_INSTALL AND NOT _lib_optix_found)
                message(WARNING "OPTIX_ROOT not set and auto-install disabled. Attempting to use OptiX SDK submodule in lib/optix-sdk...")
            endif()
            if(_lib_optix_found)
                set(_optix_root "${_lib_optix_root}")
                message(NOTICE "Found Optix library: ${_lib_optix_root}")
            else()
                message(FATAL_ERROR "OPTIX_ROOT or ENV{OPTIX_HOME} not set, auto-install off and no optix folder found in lib/.")
            endif()
        elseif(OPTIX_AUTO_INSTALL AND NOT _lib_optix_found)
            message(WARNING "OPTIX_ROOT not set, auto-install enabled. Attempting to use auto-install OptiX SDK submodule in lib/optix-sdk...")

            set(_lib_optix_root "${SEARCH_ROOT_LIST_DIR}/../lib/optix-sdk")
            if(NOT EXISTS "${_lib_optix_root}") # Clone it only if not already present
                if(OPTIX_AUTO_INSTALL)
                    set(_optix_lib_dir "${SEARCH_ROOT_LIST_DIR}/../lib")
                    file(MAKE_DIRECTORY "${_optix_lib_dir}")
                    
                    message(STATUS "Adding OptiX SDK submodule in ${_optix_lib_dir}")
                    execute_process(
                        COMMAND git submodule add "${OPTIX_SDK_REPO}" "optix-sdk"
                        WORKING_DIRECTORY "${_optix_lib_dir}"
                        RESULT_VARIABLE _optix_git_result
                        OUTPUT_VARIABLE _optix_git_out
                        ERROR_VARIABLE _optix_git_err
                    )
                    if(NOT _optix_git_result EQUAL 0)
                        message(WARNING "Failed to add OptiX SDK submodule: ${_optix_git_err}")
                    endif()
                else()
                    message(FATAL_ERROR "OptiX SDK not found. Set OPTIX_AUTO_INSTALL=ON to add ${OPTIX_SDK_REPO} as a submodule in lib/, or set OPTIX_ROOT/OPTIX_HOME.")
                endif()
            endif()
        endif()

        if(EXISTS "${_lib_optix_root}")
            set(_optix_root "${_lib_optix_root}")
        endif()
    endif()

    if(NOT _optix_root OR NOT EXISTS "${_optix_root}/include")
        message(FATAL_ERROR "OptiX SDK not found. Set OPTIX_ROOT or OPTIX_HOME.")
    endif()

    if(NOT OPTIX_ROOT)
        set(OPTIX_ROOT "${_optix_root}" CACHE PATH "OptiX SDK root")
    endif()

    # Include SDK directories (typically used) TBC
    # TODO improve this, only select what's needed and without duplicates
    set(_optix_includes
        "${_optix_root}/include"
        "${_optix_root}/SDK"
        "${_optix_root}/SDK/sutil"
        "${_optix_root}/SDK/support"
        "${_optix_root}/SDK/optixConsole"
    )
    foreach(_dir IN LISTS _optix_includes)
        if(NOT EXISTS "${_dir}")
            list(REMOVE_ITEM _optix_includes "${_dir}")
        endif()
    endforeach()

    # Add include dirs and definitions to the target
    #target_include_directories(${HOPT_TARGET} INTERFACE ${_optix_includes})
    target_compile_definitions(${HOPT_TARGET} INTERFACE __OPTIX_ENABLED__=1)

    # Define include directories for install compatibility
    #target_include_directories(${HOPT_TARGET} INTERFACE 
    #                        $<BUILD_INTERFACE:"single_entry">  # Used during development
    #                        #$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/lib/stb_PeterCdev>  
    #                        #$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/lib/rapidyaml_PeterCdev>
    #                        #$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/lib/gdt>
    #                        #$<BUILD_INTERFACE:${CUDA_INCLUDE_DIRS}> 
    #                        #$<BUILD_INTERFACE:${OPTIX_INCLUDE_DIR}>   
    #                        #$<BUILD_INTERFACE:${OpenCV_INCLUDE_DIRS}>  # Add OpenCV include directories
    #                        $<INSTALL_INTERFACE:include/optix>  # Used in installed projects
    #)

    foreach(_inc ${_optix_includes})
        target_include_directories(${HOPT_TARGET} INTERFACE
            $<BUILD_INTERFACE:${_inc}>
        )
    endforeach()

    target_include_directories(${HOPT_TARGET} INTERFACE
        $<INSTALL_INTERFACE:include/optix>
    )

    if(HOPT_CUDA_TARGET)
        #target_include_directories(${HOPT_CUDA_TARGET} INTERFACE ${_optix_includes})
        target_compile_definitions(${HOPT_CUDA_TARGET} INTERFACE __OPTIX_ENABLED__=1)
    endif()

    message(STATUS "OptiX enabled")
    message(STATUS "OPTIX_ROOT: ${_optix_root}")
    message(STATUS "OptiX_INCLUDE_DIRS: ${_optix_includes}")

    set(OPTIX_ROOT "${_optix_root}" PARENT_SCOPE)
    set(OPTIX_HOME "${_optix_root}" PARENT_SCOPE)
    set(OptiX_INSTALL_DIR "${_optix_root}" PARENT_SCOPE)
    set(OptiX_INCLUDE_DIRS "${_optix_includes}" PARENT_SCOPE)
    set(OptiX_FOUND ON PARENT_SCOPE)
endfunction()
