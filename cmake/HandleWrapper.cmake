# CMake configuration to handle Python and MATLAB wrapper configuration
include_guard(GLOBAL)

include(ExternalProject)

# Function to set python target properties
function(set_python_target_properties PYTHON_TARGET OUTPUT_NAME OUTPUT_DIRECTORY)
  set_target_properties(${PYTHON_TARGET} PROPERTIES
      INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib"
      INSTALL_RPATH_USE_LINK_PATH TRUE
      OUTPUT_NAME "${OUTPUT_NAME}"
      LIBRARY_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}"
      DEBUG_POSTFIX ""
      RELWITHDEBINFO_POSTFIX ""
      TIMING_POSTFIX ""
      PROFILING_POSTFIX ""
  )
endfunction()

# Function to check validity of interface files list
function(check_interface_files_validity VALIDITY_BOOL)
  set(_interface_files ${ARGN})
  set(_is_valid TRUE)

  if("${_interface_files}" STREQUAL "")
    set(_is_valid FALSE)
  endif()

  foreach(_path IN LISTS _interface_files)
    if(NOT _path MATCHES "\\.i$")
      set(_is_valid FALSE)
      break()
    endif()
    if(NOT EXISTS "${_path}")
      message(WARNING "Wrapper interface file does not exist: ${_path}")
      set(_is_valid FALSE)
      break()
    endif()
  endforeach()

  set(${VALIDITY_BOOL} ${_is_valid} PARENT_SCOPE)
endfunction()

# Function to resolve wrap dependency
function(resolve_local_wrap_root OUT_VAR)
  set(_preferred_root "")
  if(ARGC GREATER 1)
    set(_preferred_root "${ARGV1}")
  endif()

  if(NOT "${_preferred_root}" STREQUAL "" AND EXISTS "${_preferred_root}/cmake/PybindWrap.cmake")
    set(${OUT_VAR} "${_preferred_root}" PARENT_SCOPE)
    return()
  endif()

  set(_candidates
      "${PROJECT_SOURCE_DIR}/wrap"
      "${PROJECT_SOURCE_DIR}/lib/wrap"
      "${CMAKE_CURRENT_SOURCE_DIR}/wrap"
      "${CMAKE_CURRENT_SOURCE_DIR}/lib/wrap")

  foreach(_candidate IN LISTS _candidates)
    if(EXISTS "${_candidate}/cmake/PybindWrap.cmake")
      set(${OUT_VAR} "${_candidate}" PARENT_SCOPE)
      return()
    endif()
  endforeach()

  set(${OUT_VAR} "" PARENT_SCOPE)
endfunction()

# Check if wrap submodule is already in place
function(maybe_init_wrap_submodule OUT_VAR)
  set(${OUT_VAR} "" PARENT_SCOPE)

  set(_gitmodules_file "${PROJECT_SOURCE_DIR}/.gitmodules")
  if(NOT EXISTS "${_gitmodules_file}")
    return()
  endif()

  set(_submodule_path "")
  file(READ "${_gitmodules_file}" _gitmodules_text)
  string(REGEX MATCH "path[ \t]*=[ \t]*lib/wrap" _has_lib_wrap "${_gitmodules_text}")
  string(REGEX MATCH "path[ \t]*=[ \t]*wrap" _has_wrap "${_gitmodules_text}")
  if(_has_lib_wrap)
    set(_submodule_path "lib/wrap")
  elseif(_has_wrap)
    set(_submodule_path "wrap")
  endif()

  if("${_submodule_path}" STREQUAL "")
    return()
  endif()

  set(_candidate_root "${PROJECT_SOURCE_DIR}/${_submodule_path}")
  if(EXISTS "${_candidate_root}/cmake/PybindWrap.cmake")
    set(${OUT_VAR} "${_candidate_root}" PARENT_SCOPE)
    return()
  endif()

  execute_process(
    COMMAND git rev-parse --is-inside-work-tree
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    RESULT_VARIABLE _git_repo_result
    OUTPUT_QUIET
    ERROR_QUIET
  )
  if(NOT _git_repo_result EQUAL 0)
    return()
  endif()

  message(STATUS "Initializing wrap submodule at '${_submodule_path}'...")
  execute_process(
    COMMAND git submodule sync --recursive
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    RESULT_VARIABLE _sync_result
  )
  execute_process(
    COMMAND git submodule update --init --recursive "${_submodule_path}"
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    RESULT_VARIABLE _update_result
  )

  if(_sync_result EQUAL 0 AND _update_result EQUAL 0 AND
     EXISTS "${_candidate_root}/cmake/PybindWrap.cmake")
    set(${OUT_VAR} "${_candidate_root}" PARENT_SCOPE)
  endif()
endfunction()

# Force repo checkout if found locally
function(sync_wrap_checkout WRAP_ROOT BRANCH)
  if(NOT EXISTS "${WRAP_ROOT}/.git")
    return()
  endif()

  execute_process(
    COMMAND git remote get-url origin
    WORKING_DIRECTORY "${WRAP_ROOT}"
    RESULT_VARIABLE _origin_result
    OUTPUT_QUIET
    ERROR_QUIET
  )
  if(NOT _origin_result EQUAL 0)
    message(WARNING "Skipping wrap sync: '${WRAP_ROOT}' has no origin remote.")
    return()
  endif()

  execute_process(
    COMMAND git fetch origin "${BRANCH}"
    WORKING_DIRECTORY "${WRAP_ROOT}"
    RESULT_VARIABLE _fetch_result
  )
  if(NOT _fetch_result EQUAL 0)
    message(WARNING "Failed to fetch wrap branch '${BRANCH}' from origin. Continuing with local checkout.")
    return()
  endif()

  execute_process(
    COMMAND git rev-parse --verify --quiet "origin/${BRANCH}"
    WORKING_DIRECTORY "${WRAP_ROOT}"
    RESULT_VARIABLE _remote_branch_result
    OUTPUT_QUIET
    ERROR_QUIET
  )
  if(NOT _remote_branch_result EQUAL 0)
    message(WARNING "Remote wrap branch 'origin/${BRANCH}' not found. Continuing with local checkout.")
    return()
  endif()

  execute_process(
    COMMAND git show-ref --verify --quiet "refs/heads/${BRANCH}"
    WORKING_DIRECTORY "${WRAP_ROOT}"
    RESULT_VARIABLE _local_branch_result
    OUTPUT_QUIET
    ERROR_QUIET
  )

  if(_local_branch_result EQUAL 0)
    execute_process(
      COMMAND git checkout "${BRANCH}"
      WORKING_DIRECTORY "${WRAP_ROOT}"
      RESULT_VARIABLE _checkout_result
    )
  else()
    execute_process(
      COMMAND git checkout -B "${BRANCH}" "origin/${BRANCH}"
      WORKING_DIRECTORY "${WRAP_ROOT}"
      RESULT_VARIABLE _checkout_result
    )
  endif()
  if(NOT _checkout_result EQUAL 0)
    message(WARNING "Failed to checkout wrap branch '${BRANCH}'. Continuing with local checkout.")
    return()
  endif()

  execute_process(
    COMMAND git pull --ff-only origin "${BRANCH}"
    WORKING_DIRECTORY "${WRAP_ROOT}"
    RESULT_VARIABLE _pull_result
  )
  if(NOT _pull_result EQUAL 0)
    message(WARNING "Failed to fast-forward wrap branch '${BRANCH}' from origin. Continuing with local checkout.")
    return()
  endif()
endfunction()

### Python and MATLAB wrapper configuration using gtwrap
# Function for common wrapper configuration
function(configure_gtwrappers_common)
  set(_gtwrap_python_option_name "${LIB_NAMESPACE}_BUILD_PYTHON_WRAPPER")
  set(_gtwrap_matlab_option_name "${LIB_NAMESPACE}_BUILD_MATLAB_WRAPPER")
  set(_gtwrap_interface_var_name "${LIB_NAMESPACE}_WRAPPER_INTERFACE_FILES")
  set(_gtwrap_top_namespace_var_name "${LIB_NAMESPACE}_GTWRAP_TOP_NAMESPACE")
  set(_gtwrap_extra_deps_var_name "${LIB_NAMESPACE}_GTWRAP_DEPENDENCY_TARGETS")
  set(_gtwrap_root_var_name "${LIB_NAMESPACE}_GTWRAP_ROOT_DIR")
  set(_gtwrap_autodiscover_option_name "${LIB_NAMESPACE}_WRAPPER_AUTODISCOVER_INTERFACE_FILES")

  if(NOT DEFINED GTWRAP_BRANCH)
    set(GTWRAP_BRANCH "master" CACHE STRING "wrap branch used when syncing local checkout")
  endif()
  if(NOT DEFINED GTWRAP_SYNC_TO_MASTER)
    option(GTWRAP_SYNC_TO_MASTER "Sync local wrap checkout to latest origin/<GTWRAP_BRANCH>" ON)
  endif()

  if(NOT DEFINED ${_gtwrap_root_var_name})
    set(${_gtwrap_root_var_name} "" CACHE PATH
        "Optional path to a local wrap checkout (contains cmake/PybindWrap.cmake)."
        FORCE)
  endif()

  set(SEARCH_DIR_WRAP "${CMAKE_CURRENT_SOURCE_DIR}/src")
  set(_default_interface_file "${SEARCH_DIR_WRAP}/wrap_interface.i")

  option(${_gtwrap_autodiscover_option_name}
         "Automatically discover wrapper interface files under src/."
         OFF)

  if(${_gtwrap_autodiscover_option_name})
    file(GLOB_RECURSE _auto_interface_files "${SEARCH_DIR_WRAP}/*.i")
    list(SORT _auto_interface_files)
    set(${_gtwrap_interface_var_name} "${_auto_interface_files}" CACHE STRING
        "Ordered list of gtwrap interface files (.i). First element is the top-level module."
        FORCE)
  elseif(NOT DEFINED ${_gtwrap_interface_var_name})
    if(EXISTS "${_default_interface_file}")
      set(${_gtwrap_interface_var_name} "${_default_interface_file}" CACHE STRING
          "Ordered list of gtwrap interface files (.i). First element is the top-level module."
          FORCE)
    else()
      set(${_gtwrap_interface_var_name} "" CACHE STRING
          "Ordered list of gtwrap interface files (.i). First element is the top-level module."
          FORCE)
    endif()
  endif()

  if(NOT DEFINED ${_gtwrap_top_namespace_var_name})
    set(${_gtwrap_top_namespace_var_name} "${PROJECT_NAME}" CACHE STRING
        "Top namespace used in gtwrap pybind code generation."
        FORCE)
  endif()

  if(NOT DEFINED ${_gtwrap_extra_deps_var_name})
    set(${_gtwrap_extra_deps_var_name} "" CACHE STRING
        "Additional CMake targets that must be built before generating wrappers."
        FORCE)
  endif()

  set(_gtwrap_interface_files ${${_gtwrap_interface_var_name}})
  check_interface_files_validity(_valid_interface_files ${_gtwrap_interface_files})

  if(NOT _valid_interface_files)
    message(WARNING
      "No valid wrapper interface files were configured in '${_gtwrap_interface_var_name}'. "
      "Disabling both Python and MATLAB wrappers.")
    set(${_gtwrap_python_option_name} OFF CACHE BOOL
        "Disable Python wrapper build due to missing interface files."
        FORCE)
    set(${_gtwrap_matlab_option_name} OFF CACHE BOOL
        "Disable MATLAB wrapper build due to missing interface files."
        FORCE)
    set(GTWRAP_INTERFACE_FILES "" PARENT_SCOPE)
    return()
  endif()

  set(WRAP_PYTHON_VERSION ${PROJECT_PYTHON_VERSION}
      CACHE STRING "The Python version to use for wrapping")

  set(_configured_wrap_root "${${_gtwrap_root_var_name}}")
  if(NOT "${_configured_wrap_root}" STREQUAL "" AND
     NOT EXISTS "${_configured_wrap_root}/cmake/PybindWrap.cmake")
    message(WARNING
      "${_gtwrap_root_var_name}='${_configured_wrap_root}' is invalid. "
      "Expected a directory containing cmake/PybindWrap.cmake. Ignoring override.")
    set(_configured_wrap_root "")
  endif()

  resolve_local_wrap_root(_local_wrap_root "${_configured_wrap_root}")
  if(NOT _local_wrap_root)
    maybe_init_wrap_submodule(_local_wrap_root)
  endif()
  if(_local_wrap_root)
    if(GTWRAP_SYNC_TO_MASTER)
      sync_wrap_checkout("${_local_wrap_root}" "${GTWRAP_BRANCH}")
    endif()
    message(STATUS "Using local wrap checkout: ${_local_wrap_root}")

    list(APPEND CMAKE_MODULE_PATH "${_local_wrap_root}/cmake")
    set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" PARENT_SCOPE)

    set(GTWRAP_PYTHON_PACKAGE_DIR "${_local_wrap_root}" CACHE PATH
        "Path to gtwrap python package root." FORCE)
    set(GTWRAP_PACKAGE_DIR "${_local_wrap_root}" CACHE INTERNAL
        "Path used by gtwrap pybind custom commands for PYTHONPATH." FORCE)
    set(GTWRAP_PYTHON_PACKAGE_DIR "${_local_wrap_root}" PARENT_SCOPE)
    set(GTWRAP_PACKAGE_DIR "${_local_wrap_root}" PARENT_SCOPE)
    set(PYBIND_WRAP_SCRIPT "${_local_wrap_root}/scripts/pybind_wrap.py" CACHE FILEPATH
        "Path to pybind11 wrapping script." FORCE)
    set(MATLAB_WRAP_SCRIPT "${_local_wrap_root}/scripts/matlab_wrap.py" CACHE FILEPATH
        "Path to MATLAB wrapping script." FORCE)
    set(PYBIND_WRAP_SCRIPT "${_local_wrap_root}/scripts/pybind_wrap.py" PARENT_SCOPE)
    set(MATLAB_WRAP_SCRIPT "${_local_wrap_root}/scripts/matlab_wrap.py" PARENT_SCOPE)

    if(NOT COMMAND gtwrap_get_python_version)
      include("${_local_wrap_root}/cmake/GtwrapUtils.cmake")
    endif()
    if(NOT COMMAND pybind_wrap)
      include("${_local_wrap_root}/cmake/PybindWrap.cmake")
    endif()
    if(NOT COMMAND wrap_and_install_library)
      include("${_local_wrap_root}/cmake/MatlabWrap.cmake")
    endif()


    if(NOT COMMAND pybind11_add_module AND EXISTS "${_local_wrap_root}/pybind11/CMakeLists.txt")
      add_subdirectory(
        "${_local_wrap_root}/pybind11"
        "python/pybind11/gtwrap_${LIB_NAMESPACE}")
    endif()

    if(EXISTS "${_local_wrap_root}/matlab.h")
      get_filename_component(_local_wrap_parent "${_local_wrap_root}" DIRECTORY)
      include_directories("${_local_wrap_parent}")
      set(GTWRAP_INCLUDE_DIR "${_local_wrap_parent}" PARENT_SCOPE)
    endif()

    set(GTWRAP_ROOT_DIR "${_local_wrap_root}" PARENT_SCOPE)
  else()
    find_package(gtwrap QUIET)
    if(gtwrap_FOUND)
      message(STATUS "Using installed gtwrap package discovered by find_package(gtwrap).")

      if(DEFINED GTWRAP_PYTHON_PACKAGE_DIR AND
         NOT "${GTWRAP_PYTHON_PACKAGE_DIR}" STREQUAL "")
        set(GTWRAP_PACKAGE_DIR "${GTWRAP_PYTHON_PACKAGE_DIR}" CACHE INTERNAL
            "Path used by gtwrap pybind custom commands for PYTHONPATH." FORCE)
        set(GTWRAP_PACKAGE_DIR "${GTWRAP_PYTHON_PACKAGE_DIR}" PARENT_SCOPE)
      endif()
      if(DEFINED PYBIND_WRAP_SCRIPT AND EXISTS "${PYBIND_WRAP_SCRIPT}")
        set(PYBIND_WRAP_SCRIPT "${PYBIND_WRAP_SCRIPT}" CACHE FILEPATH
            "Path to pybind11 wrapping script." FORCE)
        set(PYBIND_WRAP_SCRIPT "${PYBIND_WRAP_SCRIPT}" PARENT_SCOPE)
      endif()
      if(DEFINED MATLAB_WRAP_SCRIPT AND EXISTS "${MATLAB_WRAP_SCRIPT}")
        set(MATLAB_WRAP_SCRIPT "${MATLAB_WRAP_SCRIPT}" CACHE FILEPATH
            "Path to MATLAB wrapping script." FORCE)
        set(MATLAB_WRAP_SCRIPT "${MATLAB_WRAP_SCRIPT}" PARENT_SCOPE)
      endif()

      if(DEFINED GTWRAP_INCLUDE_DIR AND EXISTS "${GTWRAP_INCLUDE_DIR}")
        include_directories("${GTWRAP_INCLUDE_DIR}")
        set(GTWRAP_INCLUDE_DIR "${GTWRAP_INCLUDE_DIR}" PARENT_SCOPE)
      elseif(DEFINED GTWRAP_INCLUDE_NAME AND IS_ABSOLUTE "${GTWRAP_INCLUDE_NAME}" AND EXISTS "${GTWRAP_INCLUDE_NAME}")
        include_directories("${GTWRAP_INCLUDE_NAME}")
        set(GTWRAP_INCLUDE_DIR "${GTWRAP_INCLUDE_NAME}" PARENT_SCOPE)
      endif()

      # Installed gtwrap layouts can place matlab.h under include/gtwrap/ or include/wrap/.
      # Wrap's generated MATLAB code expects <wrap/matlab.h>, so add the parent include root.
      set(_installed_matlab_h_candidates "")
      if(DEFINED GTWRAP_INCLUDE_DIR AND NOT "${GTWRAP_INCLUDE_DIR}" STREQUAL "")
        list(APPEND _installed_matlab_h_candidates
             "${GTWRAP_INCLUDE_DIR}/matlab.h"
             "${GTWRAP_INCLUDE_DIR}/gtwrap/matlab.h"
             "${GTWRAP_INCLUDE_DIR}/wrap/matlab.h")
      endif()
      if(DEFINED GTWRAP_INCLUDE_NAME AND NOT "${GTWRAP_INCLUDE_NAME}" STREQUAL "")
        list(APPEND _installed_matlab_h_candidates
             "${GTWRAP_INCLUDE_NAME}/matlab.h"
             "${GTWRAP_INCLUDE_NAME}/gtwrap/matlab.h"
             "${GTWRAP_INCLUDE_NAME}/wrap/matlab.h")
      endif()
      if(DEFINED MATLAB_WRAP_SCRIPT AND EXISTS "${MATLAB_WRAP_SCRIPT}")
        get_filename_component(_gtwrap_bin_gtwrap_dir "${MATLAB_WRAP_SCRIPT}" DIRECTORY)
        get_filename_component(_gtwrap_bin_dir "${_gtwrap_bin_gtwrap_dir}" DIRECTORY)
        get_filename_component(_gtwrap_prefix_dir "${_gtwrap_bin_dir}" DIRECTORY)
        list(APPEND _installed_matlab_h_candidates
             "${_gtwrap_prefix_dir}/include/gtwrap/matlab.h"
             "${_gtwrap_prefix_dir}/include/wrap/matlab.h")
      endif()
      if(DEFINED GTWRAP_PYTHON_PACKAGE_DIR AND EXISTS "${GTWRAP_PYTHON_PACKAGE_DIR}")
        get_filename_component(_gtwrap_lib_dir "${GTWRAP_PYTHON_PACKAGE_DIR}" DIRECTORY)
        get_filename_component(_gtwrap_prefix_dir_from_lib "${_gtwrap_lib_dir}" DIRECTORY)
        list(APPEND _installed_matlab_h_candidates
             "${_gtwrap_prefix_dir_from_lib}/include/gtwrap/matlab.h"
             "${_gtwrap_prefix_dir_from_lib}/include/wrap/matlab.h")
      endif()

      set(_installed_matlab_h "")
      foreach(_candidate IN LISTS _installed_matlab_h_candidates)
        if(EXISTS "${_candidate}")
          set(_installed_matlab_h "${_candidate}")
          break()
        endif()
      endforeach()
      if(NOT "${_installed_matlab_h}" STREQUAL "")
        get_filename_component(_installed_matlab_h_dir "${_installed_matlab_h}" DIRECTORY)
        get_filename_component(_installed_matlab_h_parent "${_installed_matlab_h_dir}" DIRECTORY)

        if(_installed_matlab_h_dir MATCHES "/(wrap|gtwrap)$")
          set(_installed_wrap_include_root "${_installed_matlab_h_parent}")
        else()
          set(_installed_wrap_include_root "${_installed_matlab_h_dir}")
        endif()

        include_directories("${_installed_wrap_include_root}")
        set(GTWRAP_INCLUDE_DIR "${_installed_wrap_include_root}" PARENT_SCOPE)
      endif()

      set(GTWRAP_ROOT_DIR "" PARENT_SCOPE)
    else()
      message(FATAL_ERROR
        "Could not locate wrap/gtwrap. Provide a local checkout at 'wrap/' or 'lib/wrap/', "
        "or set ${_gtwrap_root_var_name}=<path>, or install gtwrap so find_package(gtwrap) succeeds.")
    endif()
  endif()

  message(STATUS "Using wrapper interface files: ${_gtwrap_interface_files}")

  set(GTWRAP_INTERFACE_FILES "${_gtwrap_interface_files}" PARENT_SCOPE)
  set(GTWRAP_TOP_NAMESPACE "${${_gtwrap_top_namespace_var_name}}" PARENT_SCOPE)
  set(GTWRAP_EXTRA_DEPENDENCY_TARGETS "${${_gtwrap_extra_deps_var_name}}" PARENT_SCOPE)
endfunction()

# Python wrapper configuration using gtwrap
function(configure_python_gtwrapper)
  message(STATUS "Configuring Python wrap...")

  if(NOT GTWRAP_INTERFACE_FILES)
    message(FATAL_ERROR "GTWRAP_INTERFACE_FILES is empty. Cannot build Python wrapper.")
  endif()

  if(NOT COMMAND pybind_wrap)
    include(PybindWrap)
  endif()

  # Resolve Python executable for gtwrap custom commands, with preference for user override
  set(_resolved_python_executable "")
  if(DEFINED Python_EXECUTABLE AND NOT "${Python_EXECUTABLE}" STREQUAL "")
    set(_resolved_python_executable "${Python_EXECUTABLE}")
  else()
    get_property(_cached_python_executable CACHE PYTHON_EXECUTABLE PROPERTY VALUE)
    if(NOT "${_cached_python_executable}" STREQUAL "")
      set(_resolved_python_executable "${_cached_python_executable}")
    endif()
  endif()
  if(NOT "${_resolved_python_executable}" STREQUAL "")
    set(PYTHON_EXECUTABLE "${_resolved_python_executable}")
  endif()

  # Set gtwrap directory to use 
  set(_gtwrap_package_dir "")
  if(DEFINED GTWRAP_PACKAGE_DIR AND NOT "${GTWRAP_PACKAGE_DIR}" STREQUAL "")
    set(_gtwrap_package_dir "${GTWRAP_PACKAGE_DIR}")
  elseif(DEFINED GTWRAP_PYTHON_PACKAGE_DIR AND
         NOT "${GTWRAP_PYTHON_PACKAGE_DIR}" STREQUAL "")
    set(_gtwrap_package_dir "${GTWRAP_PYTHON_PACKAGE_DIR}")
  elseif(DEFINED GTWRAP_ROOT_DIR AND NOT "${GTWRAP_ROOT_DIR}" STREQUAL "")
    set(_gtwrap_package_dir "${GTWRAP_ROOT_DIR}")
  endif()

  if(NOT "${_gtwrap_package_dir}" STREQUAL "")
    set(GTWRAP_PACKAGE_DIR "${_gtwrap_package_dir}" CACHE INTERNAL
        "Path used by gtwrap pybind custom commands for PYTHONPATH." FORCE)
    set(GTWRAP_PACKAGE_DIR "${_gtwrap_package_dir}")
  endif()

  # Ensure pybind11 is available if targets are not found in the current build
  if(NOT COMMAND pybind11_add_module AND
     NOT TARGET pybind11_headers AND
     NOT TARGET pybind11::headers AND
     NOT TARGET pybind11::module)
    find_package(pybind11 CONFIG QUIET)
  endif()

  # Define command to generate Python wrapper using gtwrap's pybind_wrap function if not found
  if(NOT COMMAND pybind11_add_module)

    function(pybind11_add_module target_name)
      add_library(${target_name} MODULE ${ARGN})
      set_target_properties(${target_name} PROPERTIES PREFIX "")

      if(TARGET pybind11::module)
        target_link_libraries(${target_name} PRIVATE pybind11::module)
      elseif(TARGET pybind11::pybind11)
        target_link_libraries(${target_name} PRIVATE pybind11::pybind11)
      elseif(DEFINED GTWRAP_ROOT_DIR AND EXISTS "${GTWRAP_ROOT_DIR}/pybind11/include")
        target_include_directories(${target_name} PRIVATE "${GTWRAP_ROOT_DIR}/pybind11/include")
      endif()

      if(TARGET Python::Module)
        target_link_libraries(${target_name} PRIVATE Python::Module)
      elseif(TARGET Python3::Module)
        target_link_libraries(${target_name} PRIVATE Python3::Module)
      endif()
    endfunction()
  endif()

  # Throw fatal error if not available
  if(NOT COMMAND pybind11_add_module)
    message(FATAL_ERROR
      "pybind11_add_module is unavailable. Ensure pybind11 is loaded from gtwrap root or installed with CMake config files.")
  endif()

  # Set up Python package and build directories, and ensure __init__.py exists for the package
  set(PROJECT_PYTHON_SOURCE_DIR "${PROJECT_SOURCE_DIR}/python")
  set(PROJECT_PYTHON_PACKAGE_DIR "${PROJECT_PYTHON_SOURCE_DIR}/${PROJECT_NAME}")
  set(PROJECT_PYTHON_BUILD_DIRECTORY "${PROJECT_BINARY_DIR}/python")
  set(PROJECT_PYTHON_BUILD_PACKAGE_DIR "${PROJECT_PYTHON_BUILD_DIRECTORY}/${PROJECT_NAME}")
  set(PROJECT_PYTHON_TARGET_NAME "${LIB_NAMESPACE}_py")

  if(NOT EXISTS "${PROJECT_PYTHON_PACKAGE_DIR}")
    message(WARNING
      "Missing python package directory '${PROJECT_PYTHON_PACKAGE_DIR}'. Creating it.")
    file(MAKE_DIRECTORY "${PROJECT_PYTHON_PACKAGE_DIR}")
  endif()

  if(NOT EXISTS "${PROJECT_PYTHON_PACKAGE_DIR}/__init__.py")
    file(WRITE
      "${PROJECT_PYTHON_PACKAGE_DIR}/__init__.py"
      "\"\"\"Python package for ${PROJECT_NAME} wrappers.\"\"\"\n")
  endif()

  file(MAKE_DIRECTORY "${PROJECT_PYTHON_BUILD_DIRECTORY}")

  # Write pyproject.toml for the Python package, using the template from the wrap checkout if available
  set(_pyproject_template "${PROJECT_PYTHON_SOURCE_DIR}/pyproject.toml.in")

  if(NOT EXISTS "${_pyproject_template}")
    message(WARNING
      "Missing python/pyproject.toml.in. Generating a minimal fallback template in the build tree.")
    set(_pyproject_template "${PROJECT_BINARY_DIR}/python/pyproject.toml.in.fallback")
    file(WRITE "${_pyproject_template}" [=[
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "@PROJECT_NAME@"
version = "@PROJECT_VERSION@"
description = "Python bindings for @PROJECT_NAME@"
requires-python = ">=3.8"

[tool.setuptools]
packages = ["@PROJECT_NAME@"]
]=])
  endif()

  configure_file(
    "${_pyproject_template}"
    "${PROJECT_PYTHON_BUILD_DIRECTORY}/pyproject.toml"
    @ONLY)

  set(_python_metadata_file "${PROJECT_PYTHON_BUILD_DIRECTORY}/pyproject.toml")

  # Write setup.py so `pip install` from the build python folder behaves as a binary package.
  set(_setup_py_template "${PROJECT_PYTHON_SOURCE_DIR}/setup.py.in")
  if(EXISTS "${_setup_py_template}")
    configure_file(
      "${_setup_py_template}"
      "${PROJECT_PYTHON_BUILD_DIRECTORY}/setup.py"
      @ONLY)
  endif()

  # This is required to avoid an error in modern pybind11 cmake scripts.
  if(POLICY CMP0057)
    cmake_policy(SET CMP0057 NEW)
  endif()

  set(_top_namespace "${GTWRAP_TOP_NAMESPACE}")
  if("${_top_namespace}" STREQUAL "")
    set(_top_namespace "${PROJECT_NAME}")
  endif()

  set(_link_libs "${LIBNAME_WRAP_TARGET}")
  set(_wrapper_dependencies "${LIBNAME_WRAP_TARGET}")

  if(GTWRAP_EXTRA_DEPENDENCY_TARGETS)
    list(APPEND _wrapper_dependencies ${GTWRAP_EXTRA_DEPENDENCY_TARGETS})
  endif()

  list(REMOVE_DUPLICATES _wrapper_dependencies)

  # wrap expects these customization headers for each interface; seed stubs in build tree.
  set(_pywrap_codegen_root "${PROJECT_BINARY_DIR}/${PROJECT_NAME}")
  file(MAKE_DIRECTORY "${_pywrap_codegen_root}/specializations")
  file(MAKE_DIRECTORY "${_pywrap_codegen_root}/preamble")

  # Generate empty specialization and preamble headers for each interface to avoid build errors if not existing
  foreach(_interface_file IN LISTS GTWRAP_INTERFACE_FILES)
    get_filename_component(_interface_name "${_interface_file}" NAME_WE)
    set(_spec_header "${_pywrap_codegen_root}/specializations/${_interface_name}.h")
    set(_preamble_header "${_pywrap_codegen_root}/preamble/${_interface_name}.h")
    if(NOT EXISTS "${_spec_header}")
      file(WRITE "${_spec_header}" "// Optional pybind specialization hooks for ${_interface_name}.\n")
    endif()
    if(NOT EXISTS "${_preamble_header}")
      file(WRITE "${_preamble_header}" "// Optional pybind preamble hooks for ${_interface_name}.\n")
    endif()
  endforeach()

  # Configure template for pybind module
  set(_pybind_module_template "${PROJECT_BINARY_DIR}/${PROJECT_NAME}.tpl")
  if(EXISTS "${PROJECT_SOURCE_DIR}/python/${PROJECT_NAME}.tpl")
    # Use the template from the source tree if it exists
    configure_file(
      "${PROJECT_SOURCE_DIR}/python/${PROJECT_NAME}.tpl"
      "${_pybind_module_template}"
      COPYONLY)
  
  elseif(EXISTS "${PROJECT_SOURCE_DIR}/${PROJECT_NAME}.tpl")
    # Fallback to looking for a template in the project root if not in python/
    configure_file(
      "${PROJECT_SOURCE_DIR}/${PROJECT_NAME}.tpl"
      "${_pybind_module_template}"
      COPYONLY)

  else()
    # Else write it
    file(WRITE "${_pybind_module_template}" [=[
#include <pybind11/eigen.h>
#include <pybind11/stl_bind.h>
#include <pybind11/pybind11.h>
#include <pybind11/operators.h>
#include <pybind11/iostream.h>
#include <pybind11/functional.h>

{includes}

{boost_class_export}

using namespace std;

namespace py = pybind11;

{submodules}

{module_def} {{
    m_.doc() = "pybind11 wrapper of {module_name}";

{submodules_init}

{wrapped_namespace}

}}
]=])
  endif()
  
  set(ENABLE_BOOST_SERIALIZATION OFF)
  
  # Get the main interface file and deduce names
  list(GET GTWRAP_INTERFACE_FILES 0 _main_interface_file)
  get_filename_component(_main_interface_name "${_main_interface_file}" NAME_WE)
  set(_main_interface_cpp "${_main_interface_name}.cpp")
  set(GTWRAP_PYTHON_GENERATED_CPP_DIR "python")

  # Call pybind wrapper generation function from gtwrap
  pybind_wrap(${PROJECT_PYTHON_TARGET_NAME}
            "${GTWRAP_INTERFACE_FILES}"
            "${_main_interface_cpp}"
            "${PROJECT_NAME}"
            "${_top_namespace}"
            ""
            "${_pybind_module_template}"
            "${_link_libs}"
            "${_wrapper_dependencies}"
            ${ENABLE_BOOST_SERIALIZATION}
          )

  # Set python target properties, include directories, and installation rules
  set_python_target_properties(
    ${PROJECT_PYTHON_TARGET_NAME}
    "${PROJECT_NAME}"
    "${PROJECT_PYTHON_BUILD_PACKAGE_DIR}")
  target_include_directories(${PROJECT_PYTHON_TARGET_NAME}
    PRIVATE
      "${PROJECT_BINARY_DIR}"
      "${PROJECT_PYTHON_BUILD_DIRECTORY}")

  copy_directory(
    "${PROJECT_PYTHON_PACKAGE_DIR}"
    "${PROJECT_PYTHON_BUILD_PACKAGE_DIR}")

  # Resolve Python install directories to support CMake installs directly into active env site-packages.
  set(_python_install_sitearch "")
  set(_python_install_sitelib "")
  execute_process(
    COMMAND ${PYTHON_EXECUTABLE} -c "import sysconfig; print(sysconfig.get_path('platlib') or '')"
    OUTPUT_VARIABLE _python_install_sitearch
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE _python_install_sitearch_result
  )
  execute_process(
    COMMAND ${PYTHON_EXECUTABLE} -c "import sysconfig; print(sysconfig.get_path('purelib') or '')"
    OUTPUT_VARIABLE _python_install_sitelib
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE _python_install_sitelib_result
  )

  set(_python_install_root "python")
  if(_python_install_sitearch_result EQUAL 0 AND NOT "${_python_install_sitearch}" STREQUAL "")
    set(_python_install_root "${_python_install_sitearch}")
  elseif(_python_install_sitelib_result EQUAL 0 AND NOT "${_python_install_sitelib}" STREQUAL "")
    set(_python_install_root "${_python_install_sitelib}")
  endif()

  # Add import test for python module if enabled
  if(ENABLE_TESTS AND BUILD_TESTING)
    set(_python_import_test_name "${LIB_NAMESPACE}_python_import")
    add_test(
      NAME ${_python_import_test_name}
      COMMAND
        ${CMAKE_COMMAND} -E env
        "PYTHONPATH=${PROJECT_PYTHON_BUILD_DIRECTORY}:$ENV{PYTHONPATH}"
        "LD_LIBRARY_PATH=${PROJECT_BINARY_DIR}/src:$ENV{LD_LIBRARY_PATH}"
        ${PYTHON_EXECUTABLE} -c "import ${PROJECT_NAME}")
    set_tests_properties(
      ${_python_import_test_name}
      PROPERTIES
        WORKING_DIRECTORY "${PROJECT_PYTHON_BUILD_DIRECTORY}")
  endif()

  install(
    TARGETS ${PROJECT_PYTHON_TARGET_NAME}
    LIBRARY DESTINATION "${_python_install_root}/${PROJECT_NAME}")

  install(
    DIRECTORY "${PROJECT_PYTHON_PACKAGE_DIR}/"
    DESTINATION "${_python_install_root}/${PROJECT_NAME}")

  if(NOT "${_python_metadata_file}" STREQUAL "")
    install(
      FILES "${_python_metadata_file}"
      DESTINATION "${_python_install_root}")
  endif()

  # Convenience target aligned with gtsam: install the wrapper with pip from build/python.
  set(_python_pip_install_target "${LIB_NAMESPACE}_python-install")
  if(NOT TARGET ${_python_pip_install_target})
    add_custom_target(
      ${_python_pip_install_target}
      COMMAND ${PYTHON_EXECUTABLE} -c "import subprocess, sys; cmd=[sys.executable, '-m', 'pip', 'install', '.']; subprocess.check_call(cmd)"
      DEPENDS ${PROJECT_PYTHON_TARGET_NAME}
      WORKING_DIRECTORY "${PROJECT_PYTHON_BUILD_DIRECTORY}"
      VERBATIM)
  endif()

  if(BUILD_AS_MAIN_PROJECT AND NOT TARGET python-install)
    add_custom_target(python-install DEPENDS ${_python_pip_install_target})
  endif()

  # Set python stubs generation target using pybind11-stubgen
  set(_python_stubs_target "${LIB_NAMESPACE}_python-stubs")
  if(NOT TARGET ${_python_stubs_target})
    add_custom_target(
      ${_python_stubs_target}
      COMMAND
        ${CMAKE_COMMAND} -E env
        "PYTHONPATH=${PROJECT_PYTHON_BUILD_DIRECTORY}:$ENV{PYTHONPATH}"
        ${PYTHON_EXECUTABLE} -m pybind11_stubgen ${PROJECT_NAME} -o .
      DEPENDS ${PROJECT_PYTHON_TARGET_NAME}
      WORKING_DIRECTORY "${PROJECT_PYTHON_BUILD_DIRECTORY}"
      VERBATIM)
  endif()

  # Add python stubs if building as main project
  if(BUILD_AS_MAIN_PROJECT)
    if(NOT TARGET python-stubs)
      add_custom_target(python-stubs DEPENDS ${_python_stubs_target})
    endif()
  endif()

endfunction()

##################################################################################################
# MATLAB wrapper configuration using gtwrap
function(configure_matlab_gtwrapper)
  message(STATUS "Configuring MATLAB wrap...")

  if(NOT GTWRAP_INTERFACE_FILES)
    message(FATAL_ERROR "GTWRAP_INTERFACE_FILES is empty. Cannot build MATLAB wrapper.")
  endif()

  set(_resolved_python_executable "")
  if(DEFINED Python_EXECUTABLE AND NOT "${Python_EXECUTABLE}" STREQUAL "")
    set(_resolved_python_executable "${Python_EXECUTABLE}")
  else()
    get_property(_cached_python_executable CACHE PYTHON_EXECUTABLE PROPERTY VALUE)
    if(NOT "${_cached_python_executable}" STREQUAL "")
      set(_resolved_python_executable "${_cached_python_executable}")
    endif()
  endif()
  if(NOT "${_resolved_python_executable}" STREQUAL "")
    set(PYTHON_EXECUTABLE "${_resolved_python_executable}")
  endif()

  if(NOT COMMAND wrap_and_install_library)
    include(MatlabWrap)
  endif()

  message(STATUS "Including MATLAB directories...")
  find_package(Matlab REQUIRED)
  set(MATLAB_MEX_INCLUDE "${Matlab_ROOT_DIR}/extern/include")

  message(STATUS "MATLAB_MEX_INCLUDE directory: ${MATLAB_MEX_INCLUDE}")
  message(STATUS "Matlab_MEX_LIBRARY directory: ${Matlab_MEX_LIBRARY}")
  message(STATUS "Matlab_MX_LIBRARY directory: ${Matlab_MX_LIBRARY}")

  include_directories(${Matlab_INCLUDE_DIRS})
  include_directories(${MATLAB_MEX_INCLUDE})
  if(DEFINED GTWRAP_INCLUDE_DIR)
    include_directories(${GTWRAP_INCLUDE_DIR})
  endif()

  if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/matlab")
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/matlab")
  endif()

  set(WRAP_MEX_BUILD_STATIC_MODULE OFF)
  set(WRAP_TOOLBOX_INSTALL_PATH "${CMAKE_CURRENT_SOURCE_DIR}/matlab")
  set(WRAP_BUILD_TYPE_POSTFIXES OFF)

  if(NOT DEFINED LIBNAME_WRAP_TARGET)
    message(FATAL_ERROR
      "LIBNAME_WRAP_TARGET variable is not defined. Cannot proceed with MATLAB wrapper build.")
  endif()

  message(STATUS "Using interface files: ${GTWRAP_INTERFACE_FILES}")
  wrap_and_install_library("${GTWRAP_INTERFACE_FILES}" "${LIBNAME_WRAP_TARGET}" "" "" "" "" OFF)
endfunction()

##################################################################################################
# Entry point function to handle gtwrap wrappers
function(handle_gtwrappers)
  set(_gtwrap_python_option_name "${LIB_NAMESPACE}_BUILD_PYTHON_WRAPPER")
  set(_gtwrap_matlab_option_name "${LIB_NAMESPACE}_BUILD_MATLAB_WRAPPER")

  if(NOT DEFINED ${_gtwrap_python_option_name})
    set(${_gtwrap_python_option_name} OFF)
  endif()
  if(NOT DEFINED ${_gtwrap_matlab_option_name})
    set(${_gtwrap_matlab_option_name} OFF)
  endif()

  if(NOT ${${_gtwrap_python_option_name}} AND NOT ${${_gtwrap_matlab_option_name}})
    return()
  endif()

  configure_gtwrappers_common()

  if(BUILD_AS_MAIN_PROJECT)
    message(STATUS "GTWRAP top namespace: ${GTWRAP_TOP_NAMESPACE}")
  endif()

  if(${${_gtwrap_python_option_name}})
    configure_python_gtwrapper()
  endif()

  if(${${_gtwrap_matlab_option_name}})
    configure_matlab_gtwrapper()
  endif()
endfunction()

##################################################################################################
### Python wrapper configuration using pybind11 directly
# TODO
function(handle_pybind11_wrapper)
endfunction()
