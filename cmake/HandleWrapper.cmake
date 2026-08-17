# Resolve gtwrap interfaces and coordinate optional Python and MATLAB wrappers.
#
# This facade owns wrapper checkout discovery, synchronization, and common
# interface configuration. Language-specific target and packaging behavior lives
# in HandlePythonWrapper.cmake and HandleMatlabWrapper.cmake.
include_guard(GLOBAL)

include(ExternalProject)
include("${CMAKE_CURRENT_LIST_DIR}/HandlePythonWrapper.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/HandleMatlabWrapper.cmake")

# Return whether every supplied wrapper interface is an existing `.i` file.
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

# Resolve an explicit or conventional project-local gtwrap checkout.
function(resolve_local_wrap_root OUT_VAR)
  set(_preferred_root "")
  if(ARGC GREATER 1)
    set(_preferred_root "${ARGV1}")
  endif()

  if(NOT "${_preferred_root}" STREQUAL "")
    get_filename_component(
      _preferred_root
      "${_preferred_root}"
      REALPATH
      BASE_DIR "${PROJECT_SOURCE_DIR}")
    if(EXISTS "${_preferred_root}/cmake/PybindWrap.cmake")
      set(${OUT_VAR} "${_preferred_root}" PARENT_SCOPE)
      return()
    endif()
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

# Initialize a declared project-local gtwrap submodule when policy permits it.
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

# Fast-forward a Git-backed local gtwrap checkout to one remote branch.
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

# Resolve shared interface, checkout, dependency, and namespace configuration.
function(configure_gtwrappers_common)
  set(_gtwrap_python_option_name "${LIB_NAMESPACE}_BUILD_PYTHON_WRAPPER")
  set(_gtwrap_matlab_option_name "${LIB_NAMESPACE}_BUILD_MATLAB_WRAPPER")
  set(_gtwrap_interface_var_name "${LIB_NAMESPACE}_WRAPPER_INTERFACE_FILES")
  set(_gtwrap_top_namespace_var_name "${LIB_NAMESPACE}_GTWRAP_TOP_NAMESPACE")
  set(_gtwrap_extra_deps_var_name "${LIB_NAMESPACE}_GTWRAP_DEPENDENCY_TARGETS")
  set(_gtwrap_runtime_deps_var_name
      "${LIB_NAMESPACE}_GTWRAP_RUNTIME_DEPENDENCY_TARGETS")
  set(_gtwrap_root_var_name "${LIB_NAMESPACE}_GTWRAP_ROOT_DIR")
  set(_gtwrap_autodiscover_option_name "${LIB_NAMESPACE}_WRAPPER_AUTODISCOVER_INTERFACE_FILES")

  set(${PROJECT_NAME}_WRAPPER_DISABLE_REASON "" CACHE INTERNAL
      "Reason why wrapper generation is disabled for the project." FORCE)
  set(${PROJECT_NAME}_WRAPPER_INTERFACE_FILES_EFFECTIVE "" CACHE INTERNAL
      "Effective wrapper interface files configured for the project." FORCE)

  if(NOT DEFINED GTWRAP_BRANCH)
    set(GTWRAP_BRANCH "master" CACHE STRING "wrap branch used when syncing local checkout")
  endif()
  if(NOT DEFINED GTWRAP_SYNC_TO_MASTER)
    option(GTWRAP_SYNC_TO_MASTER
           "Request synchronization of wrap to origin/<GTWRAP_BRANCH>"
           OFF)
  endif()
  if(NOT DEFINED GTWRAP_MAINTENANCE_UPDATE)
    option(GTWRAP_MAINTENANCE_UPDATE
           "Explicitly permit configure-time maintenance of a local wrap checkout"
           OFF)
  endif()
  if(NOT DEFINED GTWRAP_INIT_SUBMODULE_IF_MISSING)
    option(GTWRAP_INIT_SUBMODULE_IF_MISSING
           "Initialize the wrap git submodule only after local search and find_package(gtwrap) both fail."
           OFF)
  endif()
  # Require an explicit maintenance grant before configure may move a local
  # checkout. A synchronization request alone must remain non-mutating.
  if(GTWRAP_SYNC_TO_MASTER AND NOT GTWRAP_MAINTENANCE_UPDATE)
    message(FATAL_ERROR
      "GTWRAP_SYNC_TO_MASTER=ON requires GTWRAP_MAINTENANCE_UPDATE=ON. "
      "Ordinary configuration must not move the wrapper checkout.")
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

  if(NOT DEFINED ${_gtwrap_runtime_deps_var_name})
    set(${_gtwrap_runtime_deps_var_name} "" CACHE STRING
        "Direct project-owned shared runtime build targets packaged beside the Python wrapper."
        FORCE)
  endif()

  set(_gtwrap_interface_files ${${_gtwrap_interface_var_name}})
  set(${PROJECT_NAME}_WRAPPER_INTERFACE_FILES_EFFECTIVE "${_gtwrap_interface_files}" CACHE INTERNAL
      "Effective wrapper interface files configured for the project." FORCE)
  check_interface_files_validity(_valid_interface_files ${_gtwrap_interface_files})

  if(NOT _valid_interface_files)
    message(WARNING
      "No valid wrapper interface files were configured in '${_gtwrap_interface_var_name}'. "
      "Disabling both Python and MATLAB wrappers.")
    set(${PROJECT_NAME}_WRAPPER_DISABLE_REASON "missing_or_invalid_interface_files" CACHE INTERNAL
        "Reason why wrapper generation is disabled for the project." FORCE)
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

  # Resolve one executable for both wrapper frontends. A normal variable takes
  # precedence over the legacy cache entry populated by some gtwrap versions.
  if(DEFINED Python_EXECUTABLE AND NOT "${Python_EXECUTABLE}" STREQUAL "")
    set(_gtwrap_python_executable "${Python_EXECUTABLE}")
  else()
    get_property(
      _gtwrap_python_executable
      CACHE PYTHON_EXECUTABLE
      PROPERTY VALUE)
  endif()
  if(NOT "${_gtwrap_python_executable}" STREQUAL "")
    set(
      PYTHON_EXECUTABLE
      "${_gtwrap_python_executable}"
      PARENT_SCOPE)
  endif()

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
    find_package(gtwrap QUIET)
    if(NOT gtwrap_FOUND AND GTWRAP_INIT_SUBMODULE_IF_MISSING)
      maybe_init_wrap_submodule(_local_wrap_root)
    endif()
  endif()
  if(_local_wrap_root)
    if(GTWRAP_SYNC_TO_MASTER AND GTWRAP_MAINTENANCE_UPDATE)
      sync_wrap_checkout("${_local_wrap_root}" "${GTWRAP_BRANCH}")
    endif()
    message(STATUS "Using local wrap checkout: ${_local_wrap_root}")

    # Current gtwrap configures the MATLAB include template in memory. Keep the
    # resolved checkout read-only and let the wrapper frontend own that logic.

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

        if(_installed_matlab_h_dir MATCHES "/gtwrap$")
          # Older generators emit <wrap/matlab.h> even when the installed
          # package uses include/gtwrap. Bridge that spelling in the build tree
          # without mutating the external installation.
          set(_installed_wrap_include_root
              "${PROJECT_BINARY_DIR}/gtwrap_include_bridge")
          file(MAKE_DIRECTORY "${_installed_wrap_include_root}/wrap")
          configure_file(
            "${_installed_matlab_h}"
            "${_installed_wrap_include_root}/wrap/matlab.h"
            COPYONLY)
        elseif(_installed_matlab_h_dir MATCHES "/wrap$")
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
        "or set ${_gtwrap_root_var_name}=<path>, or install gtwrap so find_package(gtwrap) succeeds. "
        "Set GTWRAP_INIT_SUBMODULE_IF_MISSING=ON to initialize a wrap submodule already declared in .gitmodules.")
    endif()
  endif()

  message(STATUS "Using wrapper interface files: ${_gtwrap_interface_files}")

  set(GTWRAP_INTERFACE_FILES "${_gtwrap_interface_files}" PARENT_SCOPE)
  set(GTWRAP_TOP_NAMESPACE "${${_gtwrap_top_namespace_var_name}}" PARENT_SCOPE)
  set(GTWRAP_EXTRA_DEPENDENCY_TARGETS "${${_gtwrap_extra_deps_var_name}}" PARENT_SCOPE)
  set(GTWRAP_RUNTIME_DEPENDENCY_TARGETS
      "${${_gtwrap_runtime_deps_var_name}}"
      PARENT_SCOPE)
endfunction()

# Configure the enabled gtwrap language frontends for the current project.
function(handle_gtwrappers)
  set(_gtwrap_python_option_name "${LIB_NAMESPACE}_BUILD_PYTHON_WRAPPER")
  set(_gtwrap_matlab_option_name "${LIB_NAMESPACE}_BUILD_MATLAB_WRAPPER")

  set(${PROJECT_NAME}_PYTHON_WRAPPER_TARGET "" CACHE INTERNAL
      "Resolved Python wrapper target name for the project." FORCE)
  set(${PROJECT_NAME}_WRAPPER_DISABLE_REASON "" CACHE INTERNAL
      "Reason why wrapper generation is disabled for the project." FORCE)

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
