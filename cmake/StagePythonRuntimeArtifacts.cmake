# Stage resolved native runtime artifacts for one Python wrapper configuration.
#
# The generated manifest reserves the wrapper extension filename and lists the
# exact runtime target files that must share its flat package directory. This
# script validates the complete namespace before copying any runtime or writing
# checkout-only metadata.
cmake_minimum_required(VERSION 3.15)

if(NOT DEFINED MANIFEST_FILE OR "${MANIFEST_FILE}" STREQUAL "")
  message(FATAL_ERROR
    "MANIFEST_FILE is required to stage Python runtime artifacts.")
endif()
if(NOT EXISTS "${MANIFEST_FILE}")
  message(FATAL_ERROR
    "Python runtime manifest does not exist: '${MANIFEST_FILE}'.")
endif()

include("${MANIFEST_FILE}")

foreach(_required_manifest_value
        PYTHON_WRAPPER_OWNER
        PYTHON_WRAPPER_PATH
        PYTHON_WRAPPER_NAME
        PYTHON_STAGING_DIRECTORY
        PYTHON_METADATA_FILE)
  if(NOT DEFINED ${_required_manifest_value}
      OR "${${_required_manifest_value}}" STREQUAL "")
    message(FATAL_ERROR
      "Python runtime manifest is missing ${_required_manifest_value}.")
  endif()
endforeach()

# Reserve the extension filename before validating runtimes so no runtime copy
# can later be overwritten when the wrapper target links.
get_filename_component(
  _resolved_wrapper_name
  "${PYTHON_WRAPPER_PATH}"
  NAME)
if(NOT "${_resolved_wrapper_name}" STREQUAL "${PYTHON_WRAPPER_NAME}")
  message(FATAL_ERROR
    "Python wrapper manifest name '${PYTHON_WRAPPER_NAME}' does not match "
    "resolved path '${PYTHON_WRAPPER_PATH}'.")
endif()

set(_destination_names "${PYTHON_WRAPPER_NAME}")
set(_destination_owners "${PYTHON_WRAPPER_OWNER}")
set(_copy_sources)
set(_copy_destinations)
set(_metadata_runtime_paths)

list(LENGTH PYTHON_RUNTIME_OWNERS _runtime_count)
list(LENGTH PYTHON_RUNTIME_SOURCES _runtime_source_count)
list(LENGTH PYTHON_RUNTIME_NAMES _runtime_name_count)
if(NOT _runtime_count EQUAL _runtime_source_count
    OR NOT _runtime_count EQUAL _runtime_name_count)
  message(FATAL_ERROR
    "Python runtime manifest has inconsistent owner, source, and name counts.")
endif()

# Validate every source and destination before creating or modifying the flat
# package directory. Duplicate entries from one owner represent a target file
# whose SONAME is identical and are staged only once.
if(_runtime_count GREATER 0)
  math(EXPR _runtime_last_index "${_runtime_count} - 1")
  foreach(_runtime_index RANGE 0 ${_runtime_last_index})
    list(GET PYTHON_RUNTIME_OWNERS ${_runtime_index} _runtime_owner)
    list(GET PYTHON_RUNTIME_SOURCES ${_runtime_index} _runtime_source)
    list(GET PYTHON_RUNTIME_NAMES ${_runtime_index} _runtime_name)

    if("${_runtime_owner}" STREQUAL ""
        OR "${_runtime_source}" STREQUAL ""
        OR "${_runtime_name}" STREQUAL "")
      message(FATAL_ERROR
        "Python runtime manifest contains an empty owner, source, or filename.")
    endif()
    if(NOT EXISTS "${_runtime_source}")
      message(FATAL_ERROR
        "Python runtime source does not exist for '${_runtime_owner}': "
        "'${_runtime_source}'.")
    endif()

    list(FIND _destination_names "${_runtime_name}" _destination_index)
    if(NOT _destination_index EQUAL -1)
      list(GET
        _destination_owners
        ${_destination_index}
        _destination_owner)
      if(NOT "${_destination_owner}" STREQUAL "${_runtime_owner}")
        message(FATAL_ERROR
          "Python runtime destination collision: '${_destination_owner}' and "
          "'${_runtime_owner}' both resolve to '${_runtime_name}' in the flat "
          "package directory.")
      endif()
      continue()
    endif()

    set(_runtime_destination
      "${PYTHON_STAGING_DIRECTORY}/${_runtime_name}")
    list(APPEND _destination_names "${_runtime_name}")
    list(APPEND _destination_owners "${_runtime_owner}")
    list(APPEND _copy_sources "${_runtime_source}")
    list(APPEND _copy_destinations "${_runtime_destination}")
    list(APPEND _metadata_runtime_paths "${_runtime_destination}")
  endforeach()
endif()

# Copy only after the complete manifest is known to be valid. All sources were
# checked above, so a validation failure cannot leave a partial staging result.
file(MAKE_DIRECTORY "${PYTHON_STAGING_DIRECTORY}")
list(LENGTH _copy_sources _copy_count)
if(_copy_count GREATER 0)
  math(EXPR _copy_last_index "${_copy_count} - 1")
  foreach(_copy_index RANGE 0 ${_copy_last_index})
    list(GET _copy_sources ${_copy_index} _copy_source)
    list(GET _copy_destinations ${_copy_index} _copy_destination)
    execute_process(
      COMMAND
        "${CMAKE_COMMAND}" -E copy_if_different
        "${_copy_source}"
        "${_copy_destination}"
      RESULT_VARIABLE _copy_result
      ERROR_VARIABLE _copy_error)
    if(NOT _copy_result EQUAL 0)
      message(FATAL_ERROR
        "Failed to stage Python runtime '${_copy_source}' as "
        "'${_copy_destination}': ${_copy_error}")
    endif()
  endforeach()
endif()

# Publish metadata only after staging succeeds, so pip and direct checkout
# imports never observe a newly generated link to incomplete runtime contents.
set(_metadata_content
"\"\"\"Generated by CMake for the latest staged Python wrapper build.\"\"\"

WRAPPER_MODULE_PATH = r\"${PYTHON_WRAPPER_PATH}\"
WRAPPER_RUNTIME_LIBRARY_PATHS = [
")
foreach(_metadata_runtime_path IN LISTS _metadata_runtime_paths)
  string(APPEND
    _metadata_content
    "    r\"${_metadata_runtime_path}\",\n")
endforeach()
string(APPEND _metadata_content "]\n")

get_filename_component(_metadata_directory "${PYTHON_METADATA_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${_metadata_directory}")
file(WRITE "${PYTHON_METADATA_FILE}" "${_metadata_content}")
