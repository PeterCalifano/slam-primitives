# Configure gtwrap Python bindings and their relocatable native runtime package.
#
# This module owns Python target layout, prefix-relative installation, exact
# project-owned runtime declarations, and generation of the resolved artifact
# manifest consumed by StagePythonRuntimeArtifacts.cmake.
include_guard(GLOBAL)

set(
  _SLAM_PRIMITIVES_PYTHON_STAGE_SCRIPT
  "${CMAKE_CURRENT_LIST_DIR}/StagePythonRuntimeArtifacts.cmake")

# Configure a Python extension to load co-located runtime libraries without
# embedding checkout or installation-prefix paths.
function(set_python_target_properties
         PYTHON_TARGET
         OUTPUT_NAME
         OUTPUT_DIRECTORY)
  if(APPLE)
    set(_python_runtime_rpath "@loader_path")
  elseif(UNIX)
    set(_python_runtime_rpath "$ORIGIN")
  else()
    set(_python_runtime_rpath "")
  endif()

  # Suppress automatic configuration subdirectories so every native artifact
  # remains co-located in the build-owned Python package.
  set_target_properties(
    "${PYTHON_TARGET}"
    PROPERTIES
      BUILD_WITH_INSTALL_RPATH TRUE
      INSTALL_RPATH "${_python_runtime_rpath}"
      INSTALL_RPATH_USE_LINK_PATH FALSE
      OUTPUT_NAME "${OUTPUT_NAME}"
      LIBRARY_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}$<0:>"
      RUNTIME_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}$<0:>"
      DEBUG_POSTFIX ""
      RELWITHDEBINFO_POSTFIX ""
      TIMING_POSTFIX ""
      PROFILING_POSTFIX "")
endfunction()

# Derive a prefix-relative site-packages root from the resolved interpreter ABI.
function(_resolve_python_install_root OUT_VAR)
  if(IS_ABSOLUTE "${CMAKE_INSTALL_LIBDIR}")
    message(FATAL_ERROR
      "CMAKE_INSTALL_LIBDIR must be relative when configuring Python "
      "wrappers so CMAKE_INSTALL_PREFIX remains the install root. Got "
      "'${CMAKE_INSTALL_LIBDIR}'.")
  endif()

  if(DEFINED Python_VERSION_MAJOR
      AND NOT "${Python_VERSION_MAJOR}" STREQUAL ""
      AND DEFINED Python_VERSION_MINOR
      AND NOT "${Python_VERSION_MINOR}" STREQUAL "")
    set(_python_resolved_version
      "${Python_VERSION_MAJOR}.${Python_VERSION_MINOR}")
  elseif(DEFINED PYTHON_VERSION_MAJOR
         AND NOT "${PYTHON_VERSION_MAJOR}" STREQUAL ""
         AND DEFINED PYTHON_VERSION_MINOR
         AND NOT "${PYTHON_VERSION_MINOR}" STREQUAL "")
    set(_python_resolved_version
      "${PYTHON_VERSION_MAJOR}.${PYTHON_VERSION_MINOR}")
  else()
    message(FATAL_ERROR
      "Cannot derive the Python install directory because the resolved "
      "interpreter major and minor versions are unavailable.")
  endif()

  set(
    "${OUT_VAR}"
    "${CMAKE_INSTALL_LIBDIR}/python${_python_resolved_version}/site-packages"
    PARENT_SCOPE)
endfunction()

# Normalize one SemVer identifier sequence for a PEP 440 local-version label.
function(_normalize_python_local_version_label OUT_VAR INPUT_VALUE)
  string(TOLOWER "${INPUT_VALUE}" _python_local_label)
  string(REGEX REPLACE "[^0-9a-z]+" "."
    _python_local_label "${_python_local_label}")
  string(REGEX REPLACE "^\\.+" ""
    _python_local_label "${_python_local_label}")
  string(REGEX REPLACE "\\.+$" ""
    _python_local_label "${_python_local_label}")
  if("${_python_local_label}" STREQUAL "")
    message(FATAL_ERROR
      "Cannot convert '${INPUT_VALUE}' to a PEP 440 local-version label.")
  endif()
  set("${OUT_VAR}" "${_python_local_label}" PARENT_SCOPE)
endfunction()

# Project structured SemVer fields into PEP 440 without changing FULL_VERSION.
function(_compose_python_package_version
         OUT_VAR VERSION_CORE VERSION_PRERELEASE VERSION_METADATA)
  if(NOT "${VERSION_CORE}" MATCHES "^[0-9]+\\.[0-9]+\\.[0-9]+$")
    message(FATAL_ERROR
      "Python package version requires a numeric SemVer core, got "
      "'${VERSION_CORE}'.")
  endif()

  set(_python_public_version "${VERSION_CORE}")
  set(_python_local_parts)
  if(NOT "${VERSION_PRERELEASE}" STREQUAL "")
    string(TOLOWER "${VERSION_PRERELEASE}" _python_prerelease)
    if(_python_prerelease MATCHES
       "^(alpha|a|beta|b|preview|pre|rc|c|dev)([.-]?([0-9]+))?$")
      set(_python_prerelease_label "${CMAKE_MATCH_1}")
      set(_python_prerelease_number "${CMAKE_MATCH_3}")
      if("${_python_prerelease_number}" STREQUAL "")
        set(_python_prerelease_number "0")
      endif()

      if(_python_prerelease_label MATCHES "^(alpha|a)$")
        set(_python_prerelease_label "a")
      elseif(_python_prerelease_label MATCHES "^(beta|b)$")
        set(_python_prerelease_label "b")
      elseif(NOT _python_prerelease_label STREQUAL "dev")
        set(_python_prerelease_label "rc")
      endif()

      if(_python_prerelease_label STREQUAL "dev")
        string(APPEND _python_public_version
          ".dev${_python_prerelease_number}")
      else()
        string(APPEND _python_public_version
          "${_python_prerelease_label}${_python_prerelease_number}")
      endif()
    else()
      # PEP 440 has no arbitrary prerelease label. Preserve its pre-release
      # ordering as dev0 and retain the SemVer identifier as local metadata.
      string(APPEND _python_public_version ".dev0")
      _normalize_python_local_version_label(
        _python_prerelease_local "${_python_prerelease}")
      list(APPEND _python_local_parts "${_python_prerelease_local}")
    endif()
  endif()

  if(NOT "${VERSION_METADATA}" STREQUAL "")
    _normalize_python_local_version_label(
      _python_metadata_local "${VERSION_METADATA}")
    list(APPEND _python_local_parts "${_python_metadata_local}")
  endif()
  if(_python_local_parts)
    string(JOIN "." _python_local_version ${_python_local_parts})
    string(APPEND _python_public_version "+${_python_local_version}")
  endif()

  set("${OUT_VAR}" "${_python_public_version}" PARENT_SCOPE)
endfunction()

# Reconstruct a build-owned Python package from stable checkout inputs.
function(_stage_python_package_sources SOURCE_DIRECTORY STAGING_DIRECTORY)
  file(REMOVE_RECURSE "${STAGING_DIRECTORY}")
  file(MAKE_DIRECTORY "${STAGING_DIRECTORY}")

  if(NOT EXISTS "${SOURCE_DIRECTORY}")
    return()
  endif()

  file(GLOB_RECURSE
    _python_source_package_files
    CONFIGURE_DEPENDS
    LIST_DIRECTORIES FALSE
    RELATIVE "${SOURCE_DIRECTORY}"
    "${SOURCE_DIRECTORY}/*")
  list(FILTER
    _python_source_package_files
    EXCLUDE REGEX
      "(^|/)(_wrapper_build\\.py|__pycache__/.*|.*\\.py[co]|.*\\.so(\\..*)?|.*\\.(dylib|dll|pyd))$")

  foreach(_python_source_package_file IN LISTS _python_source_package_files)
    get_filename_component(
      _python_source_package_subdir
      "${_python_source_package_file}"
      DIRECTORY)
    file(MAKE_DIRECTORY
      "${STAGING_DIRECTORY}/${_python_source_package_subdir}")
    configure_file(
      "${SOURCE_DIRECTORY}/${_python_source_package_file}"
      "${STAGING_DIRECTORY}/${_python_source_package_file}"
      COPYONLY)
  endforeach()
endfunction()

# Configure one collision-safe staging operation for a Python extension.
#
# PYTHON_TARGET is the extension whose resolved filename reserves the package
# namespace. STAGING_DIRECTORY receives declared runtimes, INSTALL_DESTINATION
# receives the same target-aware CMake installs, and METADATA_FILE links direct
# checkout imports and wheel construction to the latest successful staging run.
function(configure_python_runtime_artifacts
         PYTHON_TARGET
         STAGING_DIRECTORY
         INSTALL_DESTINATION
         METADATA_FILE)
  if(NOT TARGET "${PYTHON_TARGET}")
    message(FATAL_ERROR
      "Python wrapper target '${PYTHON_TARGET}' does not exist.")
  endif()
  if("${METADATA_FILE}" STREQUAL "")
    message(FATAL_ERROR
      "Python wrapper target '${PYTHON_TARGET}' requires a metadata file.")
  endif()

  if(APPLE)
    set(_python_dependency_rpath "@loader_path")
  elseif(UNIX)
    set(_python_dependency_rpath "$ORIGIN")
  else()
    set(_python_dependency_rpath "")
  endif()

  set(_python_runtime_targets ${ARGN})
  list(REMOVE_DUPLICATES _python_runtime_targets)
  set(_python_manifest_content
"set(PYTHON_WRAPPER_OWNER [==[${PYTHON_TARGET}]==])
set(PYTHON_WRAPPER_PATH [==[$<TARGET_FILE:${PYTHON_TARGET}>]==])
set(PYTHON_WRAPPER_NAME [==[$<TARGET_FILE_NAME:${PYTHON_TARGET}>]==])
set(PYTHON_STAGING_DIRECTORY [==[${STAGING_DIRECTORY}]==])
set(PYTHON_METADATA_FILE [==[${METADATA_FILE}]==])
set(PYTHON_RUNTIME_OWNERS)
set(PYTHON_RUNTIME_SOURCES)
set(PYTHON_RUNTIME_NAMES)
")

  foreach(_python_runtime_target IN LISTS _python_runtime_targets)
    if(NOT TARGET "${_python_runtime_target}")
      message(FATAL_ERROR
        "Python runtime dependency target '${_python_runtime_target}' does not "
        "exist.")
    endif()

    get_target_property(
      _python_runtime_aliased_target
      "${_python_runtime_target}"
      ALIASED_TARGET)
    if(_python_runtime_aliased_target)
      message(FATAL_ERROR
        "Python runtime dependency target '${_python_runtime_target}' is an "
        "alias. Declare its project-owned target directly.")
    endif()

    get_target_property(
      _python_runtime_imported
      "${_python_runtime_target}"
      IMPORTED)
    if(_python_runtime_imported)
      message(FATAL_ERROR
        "Python runtime dependency target '${_python_runtime_target}' is "
        "imported. Only project-owned targets can be packaged.")
    endif()

    get_target_property(
      _python_runtime_type
      "${_python_runtime_target}"
      TYPE)
    if(NOT _python_runtime_type STREQUAL "SHARED_LIBRARY"
        AND NOT _python_runtime_type STREQUAL "MODULE_LIBRARY")
      message(FATAL_ERROR
        "Python runtime dependency target '${_python_runtime_target}' has "
        "unsupported type '${_python_runtime_type}'. Expected SHARED_LIBRARY "
        "or MODULE_LIBRARY.")
    endif()

    # CMake resolves the platform, configuration, prefix, suffix, version, and
    # generator-expression rules embedded in these manifest entries.
    string(APPEND _python_manifest_content
"list(APPEND PYTHON_RUNTIME_OWNERS [==[${_python_runtime_target}]==])
list(APPEND PYTHON_RUNTIME_SOURCES [==[$<TARGET_FILE:${_python_runtime_target}>]==])
list(APPEND PYTHON_RUNTIME_NAMES [==[$<TARGET_FILE_NAME:${_python_runtime_target}>]==])
")

    get_target_property(
      _python_runtime_soversion
      "${_python_runtime_target}"
      SOVERSION)
    get_target_property(
      _python_runtime_no_soname
      "${_python_runtime_target}"
      NO_SONAME)
    if(UNIX
        AND NOT _python_runtime_soversion STREQUAL
                "_python_runtime_soversion-NOTFOUND"
        AND NOT _python_runtime_no_soname)
      string(APPEND _python_manifest_content
"list(APPEND PYTHON_RUNTIME_OWNERS [==[${_python_runtime_target}]==])
list(APPEND PYTHON_RUNTIME_SOURCES [==[$<TARGET_FILE:${_python_runtime_target}>]==])
list(APPEND PYTHON_RUNTIME_NAMES [==[$<TARGET_SONAME_FILE_NAME:${_python_runtime_target}>]==])
")
    endif()
  endforeach()

  # All packaged runtimes use the same loader-relative search contract and
  # target-aware install operation.
  if(_python_runtime_targets)
    set_target_properties(
      ${_python_runtime_targets}
      PROPERTIES
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "${_python_dependency_rpath}"
        INSTALL_RPATH_USE_LINK_PATH FALSE)
    install(
      TARGETS ${_python_runtime_targets}
      LIBRARY DESTINATION "${INSTALL_DESTINATION}" NAMELINK_SKIP
      RUNTIME DESTINATION "${INSTALL_DESTINATION}")
  endif()

  string(
    MAKE_C_IDENTIFIER
    "${PYTHON_TARGET}_python_runtime_stage"
    _python_runtime_stage_target)
  if(TARGET "${_python_runtime_stage_target}")
    message(FATAL_ERROR
      "Python runtime staging target '${_python_runtime_stage_target}' already "
      "exists.")
  endif()

  set(_python_manifest_directory
    "${CMAKE_CURRENT_BINARY_DIR}/python_runtime_manifests")
  set(_python_manifest_file
    "${_python_manifest_directory}/${_python_runtime_stage_target}_$<CONFIG>.cmake")
  file(GENERATE
    OUTPUT "${_python_manifest_file}"
    CONTENT "${_python_manifest_content}")

  # Always run staging when the wrapper target is requested so an unlinked,
  # explicitly declared runtime refreshes without forcing the extension to
  # relink. Runtime target dependencies guarantee the manifest sources exist.
  add_custom_target(
    "${_python_runtime_stage_target}"
    COMMAND
      "${CMAKE_COMMAND}"
      "-DMANIFEST_FILE=${_python_manifest_file}"
      -P "${_SLAM_PRIMITIVES_PYTHON_STAGE_SCRIPT}"
    DEPENDS ${_python_runtime_targets}
    COMMENT "Validating and staging Python runtime artifacts"
    VERBATIM)
  add_dependencies("${PYTHON_TARGET}" "${_python_runtime_stage_target}")

  # Prevent a stale link file from surviving a fresh configuration whose
  # wrapper target has not yet completed staging.
  file(REMOVE "${METADATA_FILE}")
endfunction()

# Configure the project's generated extension, source package, tests, and
# installation targets after common gtwrap resolution has completed.
function(configure_python_gtwrapper)
  message(STATUS "Configuring Python wrap...")

  if(NOT GTWRAP_INTERFACE_FILES)
    message(FATAL_ERROR
      "GTWRAP_INTERFACE_FILES is empty. Cannot build Python wrapper.")
  endif()

  if(NOT COMMAND pybind_wrap)
    include(PybindWrap)
  endif()

  # Select the package root used by gtwrap's Python custom commands.
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

  # Reuse an existing pybind11 target or discover its package configuration.
  if(NOT COMMAND pybind11_add_module AND
      NOT TARGET pybind11_headers AND
      NOT TARGET pybind11::headers AND
      NOT TARGET pybind11::module)
    find_package(pybind11 CONFIG QUIET)
  endif()

  # Provide the narrow target-construction command expected by older gtwrap
  # checkouts when their bundled pybind11 does not export it.
  if(NOT COMMAND pybind11_add_module)
    # Create one extension target and attach whichever pybind11 and Python
    # module targets are available in the current dependency layout.
    function(pybind11_add_module target_name)
      add_library(${target_name} MODULE ${ARGN})
      set_target_properties(${target_name} PROPERTIES PREFIX "")

      if(TARGET pybind11::module)
        target_link_libraries(${target_name} PRIVATE pybind11::module)
      elseif(TARGET pybind11::pybind11)
        target_link_libraries(${target_name} PRIVATE pybind11::pybind11)
      elseif(DEFINED GTWRAP_ROOT_DIR
             AND EXISTS "${GTWRAP_ROOT_DIR}/pybind11/include")
        target_include_directories(
          ${target_name}
          PRIVATE "${GTWRAP_ROOT_DIR}/pybind11/include")
      endif()

      if(TARGET Python::Module)
        target_link_libraries(${target_name} PRIVATE Python::Module)
      elseif(TARGET Python3::Module)
        target_link_libraries(${target_name} PRIVATE Python3::Module)
      endif()
    endfunction()
  endif()

  if(NOT COMMAND pybind11_add_module)
    message(FATAL_ERROR
      "pybind11_add_module is unavailable. Ensure pybind11 is loaded from the "
      "gtwrap root or installed with CMake config files.")
  endif()

  # Establish separate source-input and build-owned package layouts. Ordinary
  # wrapper configuration must not materialize generated files in the checkout.
  if(NOT DEFINED PROJECT_PYTHON_PACKAGE_NAME
      OR "${PROJECT_PYTHON_PACKAGE_NAME}" STREQUAL "")
    message(FATAL_ERROR
      "PROJECT_PYTHON_PACKAGE_NAME must identify the importable Python package.")
  endif()

  set(PROJECT_PYTHON_SOURCE_DIR "${PROJECT_SOURCE_DIR}/python")
  set(PROJECT_PYTHON_PACKAGE_DIR
    "${PROJECT_PYTHON_SOURCE_DIR}/${PROJECT_PYTHON_PACKAGE_NAME}")
  set(PROJECT_PYTHON_BUILD_DIRECTORY "${PROJECT_BINARY_DIR}/python")
  set(PROJECT_PYTHON_BUILD_PACKAGE_DIR
    "${PROJECT_PYTHON_BUILD_DIRECTORY}/${PROJECT_PYTHON_PACKAGE_NAME}")
  set(PROJECT_PYTHON_BUILD_METADATA_FILE
    "${PROJECT_PYTHON_BUILD_DIRECTORY}/pyproject.toml")
  set(PROJECT_PYTHON_BUILD_SETUP_FILE
    "${PROJECT_PYTHON_BUILD_DIRECTORY}/setup.py")
  set(PROJECT_PYTHON_WRAPPER_LINK_FILE
    "${PROJECT_PYTHON_BUILD_PACKAGE_DIR}/_wrapper_build.py")
  set(PROJECT_PYTHON_TARGET_NAME "${LIB_NAMESPACE}_py")
  set(
    ${PROJECT_NAME}_PYTHON_WRAPPER_TARGET
    "${PROJECT_PYTHON_TARGET_NAME}"
    CACHE INTERNAL
      "Resolved Python wrapper target name for the project." FORCE)

  # Stage stable package sources into the build tree while excluding stale
  # generated/import-cache artifacts that may exist in an older checkout.
  _stage_python_package_sources(
    "${PROJECT_PYTHON_PACKAGE_DIR}"
    "${PROJECT_PYTHON_BUILD_PACKAGE_DIR}")
  if(NOT EXISTS "${PROJECT_PYTHON_PACKAGE_DIR}")
    message(WARNING
      "Missing python package directory '${PROJECT_PYTHON_PACKAGE_DIR}'. "
      "Generating a minimal package in the build tree.")
  endif()

  if(NOT EXISTS "${PROJECT_PYTHON_BUILD_PACKAGE_DIR}/__init__.py")
    string(CONFIGURE [=[
"""Python package entrypoint for @PROJECT_PYTHON_PACKAGE_NAME@ bindings."""

from __future__ import annotations

HAS_WRAPPER = False
WRAPPER_IMPORT_ERROR: ImportError | None = None

try:
    from .@PROJECT_PYTHON_PACKAGE_NAME@ import *  # noqa: F401,F403
except ImportError as exc:
    WRAPPER_IMPORT_ERROR = exc
else:
    HAS_WRAPPER = True
]=] _default_python_package_init @ONLY)
    file(WRITE
      "${PROJECT_PYTHON_BUILD_PACKAGE_DIR}/__init__.py"
      "${_default_python_package_init}")
  endif()

  # Materialize build metadata beside the staged package so pip and CMake use
  # one complete, disposable packaging root.
  _compose_python_package_version(
    PYTHON_PACKAGE_VERSION
    "${PROJECT_VERSION_CORE}"
    "${PROJECT_VERSION_PRERELEASE}"
    "${PROJECT_VERSION_METADATA}")
  set(_pyproject_template "${PROJECT_PYTHON_SOURCE_DIR}/pyproject.toml.in")

  if(NOT EXISTS "${_pyproject_template}")
    message(WARNING
      "Missing python/pyproject.toml.in. Generating a minimal fallback "
      "template.")
    set(_pyproject_template
      "${PROJECT_BINARY_DIR}/python/pyproject.toml.in.fallback")
    file(WRITE "${_pyproject_template}" [=[
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "@PROJECT_PYTHON_PACKAGE_NAME@"
version = "@PYTHON_PACKAGE_VERSION@"
description = "Python bindings for @PROJECT_NAME@"
requires-python = ">=@PROJECT_PYTHON_VERSION@"

[tool.setuptools]
packages = ["@PROJECT_PYTHON_PACKAGE_NAME@"]
include-package-data = true

[tool.setuptools.package-data]
"@PROJECT_PYTHON_PACKAGE_NAME@" = [
  "*.so", "*.so.*", "*.pyd", "*.dll", "*.dylib", "*.pyi", "**/*.pyi"]
]=])
  endif()

  configure_file(
    "${_pyproject_template}"
    "${PROJECT_PYTHON_BUILD_METADATA_FILE}"
    @ONLY)

  # Keep setup.py as a compatibility entrypoint for tooling that has not moved
  # fully to pyproject.toml.
  set(_setup_py_template "${PROJECT_PYTHON_SOURCE_DIR}/setup.py.in")
  if(EXISTS "${_setup_py_template}")
    configure_file(
      "${_setup_py_template}"
      "${PROJECT_PYTHON_BUILD_SETUP_FILE}"
      @ONLY)
  else()
    set(_generated_setup_py_template
      "${PROJECT_BINARY_DIR}/python/setup.py.in.fallback")
    file(WRITE "${_generated_setup_py_template}" [=[
from setuptools import setup

setup(zip_safe=False)
]=])
    configure_file(
      "${_generated_setup_py_template}"
      "${PROJECT_PYTHON_BUILD_SETUP_FILE}"
      @ONLY)
  endif()

  # Modern pybind11 uses IN_LIST and therefore requires CMP0057's new behavior.
  if(POLICY CMP0057)
    cmake_policy(SET CMP0057 NEW)
  endif()

  set(_top_namespace "${GTWRAP_TOP_NAMESPACE}")
  if("${_top_namespace}" STREQUAL "")
    set(_top_namespace "${PROJECT_PYTHON_PACKAGE_NAME}")
  endif()

  set(_link_libs "${LIBNAME_WRAP_TARGET}")
  set(_wrapper_dependencies "${LIBNAME_WRAP_TARGET}")

  if(GTWRAP_EXTRA_DEPENDENCY_TARGETS)
    list(APPEND _wrapper_dependencies ${GTWRAP_EXTRA_DEPENDENCY_TARGETS})
  endif()

  list(REMOVE_DUPLICATES _wrapper_dependencies)

  # Seed optional customization headers expected by gtwrap without writing
  # generated hooks into the source tree.
  set(_pywrap_codegen_root
    "${PROJECT_BINARY_DIR}/${PROJECT_PYTHON_PACKAGE_NAME}")
  file(MAKE_DIRECTORY "${_pywrap_codegen_root}/specializations")
  file(MAKE_DIRECTORY "${_pywrap_codegen_root}/preamble")

  foreach(_interface_file IN LISTS GTWRAP_INTERFACE_FILES)
    get_filename_component(_interface_name "${_interface_file}" NAME_WE)
    set(_spec_header
      "${_pywrap_codegen_root}/specializations/${_interface_name}.h")
    set(_preamble_header
      "${_pywrap_codegen_root}/preamble/${_interface_name}.h")
    if(NOT EXISTS "${_spec_header}")
      file(WRITE
        "${_spec_header}"
        "// Optional pybind specialization hooks for ${_interface_name}.\n")
    endif()
    if(NOT EXISTS "${_preamble_header}")
      file(WRITE
        "${_preamble_header}"
        "// Optional pybind preamble hooks for ${_interface_name}.\n")
    endif()
  endforeach()

  # Prefer a project-owned module template and otherwise provide the generic
  # gtwrap expansion points.
  set(_pybind_module_template
    "${PROJECT_BINARY_DIR}/${PROJECT_PYTHON_PACKAGE_NAME}.tpl")
  if(EXISTS
     "${PROJECT_SOURCE_DIR}/python/${PROJECT_PYTHON_PACKAGE_NAME}.tpl")
    configure_file(
      "${PROJECT_SOURCE_DIR}/python/${PROJECT_PYTHON_PACKAGE_NAME}.tpl"
      "${_pybind_module_template}"
      COPYONLY)
  elseif(EXISTS "${PROJECT_SOURCE_DIR}/${PROJECT_PYTHON_PACKAGE_NAME}.tpl")
    configure_file(
      "${PROJECT_SOURCE_DIR}/${PROJECT_PYTHON_PACKAGE_NAME}.tpl"
      "${_pybind_module_template}"
      COPYONLY)
  else()
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

  # Derive gtwrap's generated translation unit from the leading interface.
  list(GET GTWRAP_INTERFACE_FILES 0 _main_interface_file)
  get_filename_component(
    _main_interface_name
    "${_main_interface_file}"
    NAME_WE)
  set(_main_interface_cpp "${_main_interface_name}.cpp")
  set(GTWRAP_PYTHON_GENERATED_CPP_DIR "python")

  # Couple optional generated docstrings to the owning Doxygen XML target.
  if(DEFINED GTWRAP_ADD_DOCSTRINGS AND GTWRAP_ADD_DOCSTRINGS)
    if(DEFINED BUILD_DOC_XML
        AND BUILD_DOC_XML
        AND DEFINED ${PROJECT_NAME}_DOXYGEN_XML_DIR)
      set(
        GTWRAP_PYTHON_DOCS_SOURCE
        "${${PROJECT_NAME}_DOXYGEN_XML_DIR}"
        CACHE PATH
          "Doxygen XML directory used for gtwrap Python docstrings." FORCE)
      message(STATUS
        "Python wrapper docstrings use project Doxygen XML: "
        "${GTWRAP_PYTHON_DOCS_SOURCE}")
    else()
      message(WARNING
        "GTWRAP_ADD_DOCSTRINGS=ON but BUILD_DOC_XML is not enabled or Doxygen "
        "XML is unavailable. Generated Python wrappers will not receive "
        "project Doxygen docstrings.")
    endif()
  endif()

  pybind_wrap(
    ${PROJECT_PYTHON_TARGET_NAME}
    "${GTWRAP_INTERFACE_FILES}"
    "${_main_interface_cpp}"
    "${PROJECT_PYTHON_PACKAGE_NAME}"
    "${_top_namespace}"
    ""
    "${_pybind_module_template}"
    "${_link_libs}"
    "${_wrapper_dependencies}"
    ${ENABLE_BOOST_SERIALIZATION})

  if(DEFINED GTWRAP_ADD_DOCSTRINGS AND GTWRAP_ADD_DOCSTRINGS AND
     TARGET "pybind_wrap_${PROJECT_PYTHON_PACKAGE_NAME}" AND
     TARGET "${LIB_NAMESPACE}_doc")
    add_dependencies(
      "pybind_wrap_${PROJECT_PYTHON_PACKAGE_NAME}"
      "${LIB_NAMESPACE}_doc")
  endif()

  # Place the extension and declared native runtimes in one relocatable package
  # namespace before configuring install and developer targets.
  set_python_target_properties(
    ${PROJECT_PYTHON_TARGET_NAME}
    "${PROJECT_PYTHON_PACKAGE_NAME}"
    "${PROJECT_PYTHON_BUILD_PACKAGE_DIR}")
  target_include_directories(${PROJECT_PYTHON_TARGET_NAME}
    PRIVATE
      "${PROJECT_BINARY_DIR}"
      "${PROJECT_PYTHON_BUILD_DIRECTORY}")

  # Keep CMake installs relocatable beneath CMAKE_INSTALL_PREFIX. Installing
  # into an active environment remains the responsibility of the pip target.
  _resolve_python_install_root(_python_install_root)
  set(_python_package_install_destination
    "${_python_install_root}/${PROJECT_PYTHON_PACKAGE_NAME}")

  # A shared main library is always a Python runtime artifact. Static and
  # interface targets are already linked into the extension and need no file.
  set(_python_runtime_targets)
  get_target_property(
    _python_main_runtime_target_type
    "${LIBNAME_WRAP_TARGET}"
    TYPE)
  if(_python_main_runtime_target_type STREQUAL "SHARED_LIBRARY"
      OR _python_main_runtime_target_type STREQUAL "MODULE_LIBRARY")
    list(APPEND _python_runtime_targets "${LIBNAME_WRAP_TARGET}")
  endif()
  if(GTWRAP_RUNTIME_DEPENDENCY_TARGETS)
    list(APPEND
      _python_runtime_targets
      ${GTWRAP_RUNTIME_DEPENDENCY_TARGETS})
  endif()

  configure_python_runtime_artifacts(
    "${PROJECT_PYTHON_TARGET_NAME}"
    "${PROJECT_PYTHON_BUILD_PACKAGE_DIR}"
    "${_python_package_install_destination}"
    "${PROJECT_PYTHON_WRAPPER_LINK_FILE}"
    ${_python_runtime_targets})

  # Exercise the staged build package against the generated link metadata.
  if(ENABLE_TESTS AND BUILD_TESTING)
    set(_python_import_test_name "${LIB_NAMESPACE}_python_import")
    string(CONCAT _python_import_test_code
        "import ${PROJECT_PYTHON_PACKAGE_NAME} as module_; "
        "assert getattr(module_, 'HAS_WRAPPER', False), "
        "'Expected HAS_WRAPPER=True';")
    add_test(
      NAME ${_python_import_test_name}
      COMMAND
        ${CMAKE_COMMAND} -E env
        "PYTHONPATH=${PROJECT_PYTHON_BUILD_DIRECTORY}:$ENV{PYTHONPATH}"
        ${PYTHON_EXECUTABLE} -c "${_python_import_test_code}")
    set_tests_properties(
      ${_python_import_test_name}
      PROPERTIES
        WORKING_DIRECTORY "${PROJECT_PYTHON_BUILD_DIRECTORY}")
  endif()

  install(
    TARGETS ${PROJECT_PYTHON_TARGET_NAME}
    LIBRARY DESTINATION "${_python_package_install_destination}"
    RUNTIME DESTINATION "${_python_package_install_destination}")

  install(
    DIRECTORY "${PROJECT_PYTHON_BUILD_PACKAGE_DIR}/"
    DESTINATION "${_python_package_install_destination}"
    PATTERN "_wrapper_build.py" EXCLUDE
    PATTERN "__pycache__" EXCLUDE
    PATTERN "*.pyc" EXCLUDE
    PATTERN "*.so*" EXCLUDE
    PATTERN "*.dylib" EXCLUDE
    PATTERN "*.dll" EXCLUDE
    PATTERN "*.pyd" EXCLUDE)

  install(
    FILES "${PROJECT_PYTHON_BUILD_METADATA_FILE}"
    DESTINATION "${_python_install_root}")

  # Install the staged package only after its native wrapper is current.
  set(_python_pip_install_target "${LIB_NAMESPACE}_python-install")
  if(NOT TARGET "${_python_pip_install_target}")
    string(CONCAT _python_pip_install_code
      "import subprocess, sys; "
      "cmd=[sys.executable, '-m', 'pip', 'install', "
      "'--no-build-isolation', '--no-deps', '.']; "
      "subprocess.check_call(cmd)")
    add_custom_target(
      "${_python_pip_install_target}"
      COMMAND
        ${PYTHON_EXECUTABLE} -c
        "${_python_pip_install_code}"
      DEPENDS "${PROJECT_PYTHON_TARGET_NAME}"
      WORKING_DIRECTORY "${PROJECT_PYTHON_BUILD_DIRECTORY}"
      VERBATIM)
  endif()

  if(BUILD_AS_MAIN_PROJECT AND NOT TARGET python-install)
    add_custom_target(python-install DEPENDS ${_python_pip_install_target})
  endif()

  # Generate stubs from the same staged package used by the import test.
  set(_python_stubs_target "${LIB_NAMESPACE}_python-stubs")
  if(NOT TARGET "${_python_stubs_target}")
    add_custom_target(
      "${_python_stubs_target}"
      COMMAND
        ${CMAKE_COMMAND} -E env
        "PYTHONPATH=${PROJECT_PYTHON_BUILD_DIRECTORY}:$ENV{PYTHONPATH}"
        ${PYTHON_EXECUTABLE} -m pybind11_stubgen
        ${PROJECT_PYTHON_PACKAGE_NAME} -o .
      DEPENDS "${PROJECT_PYTHON_TARGET_NAME}"
      WORKING_DIRECTORY "${PROJECT_PYTHON_BUILD_DIRECTORY}"
      VERBATIM)
  endif()

  if(BUILD_AS_MAIN_PROJECT AND NOT TARGET python-stubs)
    add_custom_target(python-stubs DEPENDS "${_python_stubs_target}")
  endif()
endfunction()
