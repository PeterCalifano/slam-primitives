# CMake configuration to extract version information from Git tags
# Fallback chain: git tags --> VERSION file --> CMake hardcoded defaults

# Try to extract version from git tags. Sets version variables in parent scope on success.
# Returns GIT_VERSION_FOUND = TRUE/FALSE in parent scope.
function(get_version_from_git)
    set(GIT_VERSION_FOUND FALSE PARENT_SCOPE)

    find_package(Git QUIET)
    if(NOT Git_FOUND)
        message(STATUS "Git not found, skipping git version extraction")
        return()
    endif()

    execute_process(
        COMMAND ${GIT_EXECUTABLE} describe --tags --always
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_TAG
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE GIT_RESULT
    )

    if(NOT GIT_RESULT EQUAL 0)
        message(STATUS "Failed to get git tag")
        return()
    endif()

    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-parse --short=7 HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_COMMIT_SHORT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    string(REGEX REPLACE "^v" "" CLEAN_TAG "${GIT_TAG}")
    if(CLEAN_TAG MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)(-.*)?$")
        set(PROJECT_VERSION_MAJOR ${CMAKE_MATCH_1} PARENT_SCOPE)
        set(PROJECT_VERSION_MINOR ${CMAKE_MATCH_2} PARENT_SCOPE)
        set(PROJECT_VERSION_PATCH ${CMAKE_MATCH_3} PARENT_SCOPE)
        set(PROJECT_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}" PARENT_SCOPE)
        set(FULL_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}+${GIT_COMMIT_SHORT_HASH}" PARENT_SCOPE)
        set(GIT_VERSION_FOUND TRUE PARENT_SCOPE)
        message(STATUS "Version from git tag: ${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}+${GIT_COMMIT_SHORT_HASH}")
    else()
        message(STATUS "Git tag '${CLEAN_TAG}' does not match semver format (vX.Y.Z)")
    endif()
endfunction()

# Try to read version from an existing VERSION file. Sets version variables in parent scope on success.
# Returns FILE_VERSION_FOUND = TRUE/FALSE in parent scope.
function(read_version_from_file VERSION_FILE_PATH)
    set(FILE_VERSION_FOUND FALSE PARENT_SCOPE)

    if(NOT EXISTS "${VERSION_FILE_PATH}")
        message(STATUS "VERSION file not found at: ${VERSION_FILE_PATH}")
        return()
    endif()

    file(READ "${VERSION_FILE_PATH}" VERSION_CONTENT)

    # Parse "Project version: X.Y.Z"
    if(VERSION_CONTENT MATCHES "Project version: ([0-9]+)\\.([0-9]+)\\.([0-9]+)")
        set(PROJECT_VERSION_MAJOR ${CMAKE_MATCH_1} PARENT_SCOPE)
        set(PROJECT_VERSION_MINOR ${CMAKE_MATCH_2} PARENT_SCOPE)
        set(PROJECT_VERSION_PATCH ${CMAKE_MATCH_3} PARENT_SCOPE)
        set(PROJECT_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}" PARENT_SCOPE)
        set(FILE_VERSION_FOUND TRUE PARENT_SCOPE)

        # Parse optional "Full version: X.Y.Z+hash"
        if(VERSION_CONTENT MATCHES "Full version: ([^\n]+)")
            set(FULL_VERSION "${CMAKE_MATCH_1}" PARENT_SCOPE)
        else()
            set(FULL_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}" PARENT_SCOPE)
        endif()

        message(STATUS "Version from VERSION file: ${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}")
    else()
        message(WARNING "VERSION file exists but could not be parsed: ${VERSION_FILE_PATH}")
    endif()
endfunction()

# Main version resolution function.
# Fallback chain: git --> VERSION file --> CMake hardcoded defaults (already set by caller)
function(resolve_project_version)
    # Try git
    get_version_from_git()
    if(GIT_VERSION_FOUND)
        # Propagate to parent scope
        set(PROJECT_VERSION_MAJOR ${PROJECT_VERSION_MAJOR} PARENT_SCOPE)
        set(PROJECT_VERSION_MINOR ${PROJECT_VERSION_MINOR} PARENT_SCOPE)
        set(PROJECT_VERSION_PATCH ${PROJECT_VERSION_PATCH} PARENT_SCOPE)
        set(PROJECT_VERSION ${PROJECT_VERSION} PARENT_SCOPE)
        set(FULL_VERSION ${FULL_VERSION} PARENT_SCOPE)
        return()
    endif()

    # Try VERSION file
    read_version_from_file("${CMAKE_SOURCE_DIR}/VERSION")
    if(FILE_VERSION_FOUND)
        set(PROJECT_VERSION_MAJOR ${PROJECT_VERSION_MAJOR} PARENT_SCOPE)
        set(PROJECT_VERSION_MINOR ${PROJECT_VERSION_MINOR} PARENT_SCOPE)
        set(PROJECT_VERSION_PATCH ${PROJECT_VERSION_PATCH} PARENT_SCOPE)
        set(PROJECT_VERSION ${PROJECT_VERSION} PARENT_SCOPE)
        set(FULL_VERSION ${FULL_VERSION} PARENT_SCOPE)
        return()
    endif()

    # Fall back to CMake hardcoded defaults (already set by caller)
    message(WARNING "No git tags or VERSION file found. Using CMake default version: ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}")
    set(FULL_VERSION "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}" PARENT_SCOPE)
endfunction()

function(compose_version_string OUT_VAR)
    # Compose version string from major, minor, patch
    set(VERSION_STRING "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}")
    set(STRING_TO_WRITE "Project version: ${VERSION_STRING}\n")

    # If FULL_VERSION is defined, append it
    if(DEFINED FULL_VERSION)
        set(STRING_TO_WRITE "${STRING_TO_WRITE}Full version: ${FULL_VERSION}\n")
    endif()

    set(${OUT_VAR} "${STRING_TO_WRITE}" PARENT_SCOPE)
endfunction()

# Function to write VERSION file in binary directory
function(write_build_VERSION_file)
    set(VERSION_FILE_PATH "${CMAKE_BINARY_DIR}/VERSION")
    set(STRING_TO_WRITE "")
    compose_version_string(STRING_TO_WRITE)
    file(WRITE "${VERSION_FILE_PATH}" "${STRING_TO_WRITE}\n")
endfunction()

# Function to write VERSION file in source directory
function(write_source_VERSION_file)
    set(VERSION_FILE_PATH "${CMAKE_SOURCE_DIR}/VERSION")
    set(STRING_TO_WRITE "")
    compose_version_string(STRING_TO_WRITE)
    file(WRITE "${VERSION_FILE_PATH}" "${STRING_TO_WRITE}\n")
endfunction()

# Function to write VERSION file in install directory
function(write_install_VERSION_file)
    set(VERSION_FILE_PATH "${CMAKE_INSTALL_PREFIX}/VERSION")
    set(STRING_TO_WRITE "")
    compose_version_string(STRING_TO_WRITE)
    file(WRITE "${VERSION_FILE_PATH}" "${STRING_TO_WRITE}\n")
endfunction()
