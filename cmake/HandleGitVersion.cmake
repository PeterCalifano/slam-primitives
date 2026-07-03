# CMake configuration to extract version information from Git tags
# Fallback chain: git tags --> VERSION file --> CMake hardcoded defaults

get_filename_component(HANDLE_GIT_VERSION_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

macro(set_version_components VERSION_MAJOR VERSION_MINOR VERSION_PATCH VERSION_PRERELEASE VERSION_METADATA)
    set(PROJECT_VERSION_MAJOR "${VERSION_MAJOR}" PARENT_SCOPE)
    set(PROJECT_VERSION_MINOR "${VERSION_MINOR}" PARENT_SCOPE)
    set(PROJECT_VERSION_PATCH "${VERSION_PATCH}" PARENT_SCOPE)
    set(PROJECT_VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}" PARENT_SCOPE)
    set(PROJECT_VERSION_CORE "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}" PARENT_SCOPE)
    set(PROJECT_VERSION_PRERELEASE "${VERSION_PRERELEASE}" PARENT_SCOPE)
    set(PROJECT_VERSION_METADATA "${VERSION_METADATA}" PARENT_SCOPE)
endmacro()

function(compose_full_version_string OUT_VAR VERSION_CORE VERSION_PRERELEASE VERSION_METADATA)
    set(FULL_VERSION_LOCAL "${VERSION_CORE}")

    if(NOT "${VERSION_PRERELEASE}" STREQUAL "")
        string(APPEND FULL_VERSION_LOCAL "-${VERSION_PRERELEASE}")
    endif()

    if(NOT "${VERSION_METADATA}" STREQUAL "")
        string(APPEND FULL_VERSION_LOCAL "+${VERSION_METADATA}")
    endif()

    set(${OUT_VAR} "${FULL_VERSION_LOCAL}" PARENT_SCOPE)
endfunction()

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
        COMMAND ${GIT_EXECUTABLE} describe --tags --long --dirty --always
        WORKING_DIRECTORY ${HANDLE_GIT_VERSION_PROJECT_ROOT}
        OUTPUT_VARIABLE GIT_TAG
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE GIT_RESULT
    )

    if(NOT GIT_RESULT EQUAL 0)
        message(STATUS "Failed to get git tag")
        return()
    endif()

    string(REGEX REPLACE "^v" "" CLEAN_TAG "${GIT_TAG}")
    if(CLEAN_TAG MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)(-([0-9A-Za-z.-]+))?-([0-9]+)-g([0-9a-f]+)(-dirty)?$")
        set(VERSION_MAJOR_LOCAL "${CMAKE_MATCH_1}")
        set(VERSION_MINOR_LOCAL "${CMAKE_MATCH_2}")
        set(VERSION_PATCH_LOCAL "${CMAKE_MATCH_3}")
        set(VERSION_PRERELEASE_LOCAL "${CMAKE_MATCH_5}")
        set(VERSION_DISTANCE_LOCAL "${CMAKE_MATCH_6}")
        set(VERSION_HASH_LOCAL "g${CMAKE_MATCH_7}")
        set(VERSION_DIRTY_LOCAL "${CMAKE_MATCH_8}")
        set(VERSION_METADATA_PARTS_LOCAL)

        if(NOT "${VERSION_DISTANCE_LOCAL}" STREQUAL "0")
            list(APPEND VERSION_METADATA_PARTS_LOCAL "${VERSION_DISTANCE_LOCAL}")
        endif()

        if(NOT "${VERSION_DISTANCE_LOCAL}" STREQUAL "0" OR NOT "${VERSION_DIRTY_LOCAL}" STREQUAL "")
            list(APPEND VERSION_METADATA_PARTS_LOCAL "${VERSION_HASH_LOCAL}")
        endif()

        if(NOT "${VERSION_DIRTY_LOCAL}" STREQUAL "")
            list(APPEND VERSION_METADATA_PARTS_LOCAL "dirty")
        endif()

        set(VERSION_METADATA_LOCAL "")
        if(VERSION_METADATA_PARTS_LOCAL)
            string(JOIN "." VERSION_METADATA_LOCAL ${VERSION_METADATA_PARTS_LOCAL})
        endif()

        set_version_components(
            "${VERSION_MAJOR_LOCAL}"
            "${VERSION_MINOR_LOCAL}"
            "${VERSION_PATCH_LOCAL}"
            "${VERSION_PRERELEASE_LOCAL}"
            "${VERSION_METADATA_LOCAL}"
        )
        compose_full_version_string(
            FULL_VERSION_LOCAL
            "${VERSION_MAJOR_LOCAL}.${VERSION_MINOR_LOCAL}.${VERSION_PATCH_LOCAL}"
            "${VERSION_PRERELEASE_LOCAL}"
            "${VERSION_METADATA_LOCAL}"
        )

        set(FULL_VERSION "${FULL_VERSION_LOCAL}" PARENT_SCOPE)
        set(GIT_VERSION_FOUND TRUE PARENT_SCOPE)

        if("${VERSION_DISTANCE_LOCAL}" STREQUAL "0" AND "${VERSION_DIRTY_LOCAL}" STREQUAL "")
            message(STATUS "Version from exact git tag: ${FULL_VERSION_LOCAL}")
        else()
            message(STATUS "Version from git describe: ${FULL_VERSION_LOCAL}")
        endif()

    elseif(CLEAN_TAG MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)(-([0-9A-Za-z.-]+))?$")
        set(VERSION_MAJOR_LOCAL "${CMAKE_MATCH_1}")
        set(VERSION_MINOR_LOCAL "${CMAKE_MATCH_2}")
        set(VERSION_PATCH_LOCAL "${CMAKE_MATCH_3}")
        set(VERSION_PRERELEASE_LOCAL "${CMAKE_MATCH_5}")

        set_version_components(
            "${VERSION_MAJOR_LOCAL}"
            "${VERSION_MINOR_LOCAL}"
            "${VERSION_PATCH_LOCAL}"
            "${VERSION_PRERELEASE_LOCAL}"
            ""
        )
        compose_full_version_string(
            FULL_VERSION_LOCAL
            "${VERSION_MAJOR_LOCAL}.${VERSION_MINOR_LOCAL}.${VERSION_PATCH_LOCAL}"
            "${VERSION_PRERELEASE_LOCAL}"
            ""
        )

        set(FULL_VERSION "${FULL_VERSION_LOCAL}" PARENT_SCOPE)
        set(GIT_VERSION_FOUND TRUE PARENT_SCOPE)
        message(STATUS "Version from git tag: ${FULL_VERSION_LOCAL}")
    else()
        message(STATUS "Git describe '${CLEAN_TAG}' does not match supported semver format (vX.Y.Z[-prerelease])")
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

    set(VERSION_MAJOR_LOCAL "")
    set(VERSION_MINOR_LOCAL "")
    set(VERSION_PATCH_LOCAL "")
    if(VERSION_CONTENT MATCHES "Project version core: ([0-9]+)\\.([0-9]+)\\.([0-9]+)")
        set(VERSION_MAJOR_LOCAL "${CMAKE_MATCH_1}")
        set(VERSION_MINOR_LOCAL "${CMAKE_MATCH_2}")
        set(VERSION_PATCH_LOCAL "${CMAKE_MATCH_3}")
    elseif(VERSION_CONTENT MATCHES "Project version: ([0-9]+)\\.([0-9]+)\\.([0-9]+)")
        set(VERSION_MAJOR_LOCAL "${CMAKE_MATCH_1}")
        set(VERSION_MINOR_LOCAL "${CMAKE_MATCH_2}")
        set(VERSION_PATCH_LOCAL "${CMAKE_MATCH_3}")
    endif()

    if(NOT "${VERSION_MAJOR_LOCAL}" STREQUAL "")
        set(VERSION_PRERELEASE_LOCAL "")
        if(VERSION_CONTENT MATCHES "Project version prerelease: ([^\n]+)")
            set(VERSION_PRERELEASE_LOCAL "${CMAKE_MATCH_1}")
            if(VERSION_PRERELEASE_LOCAL STREQUAL "<none>")
                set(VERSION_PRERELEASE_LOCAL "")
            endif()
        endif()

        set(VERSION_METADATA_LOCAL "")
        if(VERSION_CONTENT MATCHES "Project version metadata: ([^\n]+)")
            set(VERSION_METADATA_LOCAL "${CMAKE_MATCH_1}")
            if(VERSION_METADATA_LOCAL STREQUAL "<none>")
                set(VERSION_METADATA_LOCAL "")
            endif()
        endif()

        set_version_components(
            "${VERSION_MAJOR_LOCAL}"
            "${VERSION_MINOR_LOCAL}"
            "${VERSION_PATCH_LOCAL}"
            "${VERSION_PRERELEASE_LOCAL}"
            "${VERSION_METADATA_LOCAL}"
        )
        set(FILE_VERSION_FOUND TRUE PARENT_SCOPE)

        if(VERSION_CONTENT MATCHES "Full version: ([^\n]+)")
            set(FULL_VERSION "${CMAKE_MATCH_1}" PARENT_SCOPE)
        else()
            compose_full_version_string(
                FULL_VERSION_LOCAL
                "${VERSION_MAJOR_LOCAL}.${VERSION_MINOR_LOCAL}.${VERSION_PATCH_LOCAL}"
                "${VERSION_PRERELEASE_LOCAL}"
                "${VERSION_METADATA_LOCAL}"
            )
            set(FULL_VERSION "${FULL_VERSION_LOCAL}" PARENT_SCOPE)
        endif()

        message(STATUS "Version from VERSION file: ${VERSION_MAJOR_LOCAL}.${VERSION_MINOR_LOCAL}.${VERSION_PATCH_LOCAL}")
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
        set(PROJECT_VERSION_CORE ${PROJECT_VERSION_CORE} PARENT_SCOPE)
        set(PROJECT_VERSION_PRERELEASE ${PROJECT_VERSION_PRERELEASE} PARENT_SCOPE)
        set(PROJECT_VERSION_METADATA ${PROJECT_VERSION_METADATA} PARENT_SCOPE)
        set(FULL_VERSION ${FULL_VERSION} PARENT_SCOPE)
        return()
    endif()

    # Try VERSION file
    read_version_from_file("${HANDLE_GIT_VERSION_PROJECT_ROOT}/VERSION")
    if(FILE_VERSION_FOUND)
        set(PROJECT_VERSION_MAJOR ${PROJECT_VERSION_MAJOR} PARENT_SCOPE)
        set(PROJECT_VERSION_MINOR ${PROJECT_VERSION_MINOR} PARENT_SCOPE)
        set(PROJECT_VERSION_PATCH ${PROJECT_VERSION_PATCH} PARENT_SCOPE)
        set(PROJECT_VERSION ${PROJECT_VERSION} PARENT_SCOPE)
        set(PROJECT_VERSION_CORE ${PROJECT_VERSION_CORE} PARENT_SCOPE)
        set(PROJECT_VERSION_PRERELEASE ${PROJECT_VERSION_PRERELEASE} PARENT_SCOPE)
        set(PROJECT_VERSION_METADATA ${PROJECT_VERSION_METADATA} PARENT_SCOPE)
        set(FULL_VERSION ${FULL_VERSION} PARENT_SCOPE)
        return()
    endif()

    # Fall back to CMake hardcoded defaults (already set by caller)
    message(WARNING "No git tags or VERSION file found. Using CMake default version: ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}")
    set(PROJECT_VERSION_CORE "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}" PARENT_SCOPE)
    set(PROJECT_VERSION_PRERELEASE "" PARENT_SCOPE)
    set(PROJECT_VERSION_METADATA "" PARENT_SCOPE)
    set(FULL_VERSION "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}" PARENT_SCOPE)
endfunction()

function(compose_version_string OUT_VAR)
    # Compose version string from major, minor, patch
    set(VERSION_STRING "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}")
    set(STRING_TO_WRITE "Project version: ${VERSION_STRING}\n")
    string(APPEND STRING_TO_WRITE "Project version core: ${VERSION_STRING}\n")

    if(DEFINED PROJECT_VERSION_PRERELEASE AND NOT "${PROJECT_VERSION_PRERELEASE}" STREQUAL "")
        string(APPEND STRING_TO_WRITE "Project version prerelease: ${PROJECT_VERSION_PRERELEASE}\n")
    else()
        string(APPEND STRING_TO_WRITE "Project version prerelease: <none>\n")
    endif()

    if(DEFINED PROJECT_VERSION_METADATA AND NOT "${PROJECT_VERSION_METADATA}" STREQUAL "")
        string(APPEND STRING_TO_WRITE "Project version metadata: ${PROJECT_VERSION_METADATA}\n")
    else()
        string(APPEND STRING_TO_WRITE "Project version metadata: <none>\n")
    endif()

    # If FULL_VERSION is defined, append it
    if(DEFINED FULL_VERSION)
        string(APPEND STRING_TO_WRITE "Full version: ${FULL_VERSION}\n")
    endif()

    set(${OUT_VAR} "${STRING_TO_WRITE}" PARENT_SCOPE)
endfunction()

# Function to write VERSION file in binary directory
function(write_build_VERSION_file)
    set(VERSION_FILE_PATH "${PROJECT_BINARY_DIR}/VERSION")
    set(STRING_TO_WRITE "")
    compose_version_string(STRING_TO_WRITE)
    file(WRITE "${VERSION_FILE_PATH}" "${STRING_TO_WRITE}\n")
endfunction()

# Function to write VERSION file in source directory
function(write_source_VERSION_file)
    set(VERSION_FILE_PATH "${HANDLE_GIT_VERSION_PROJECT_ROOT}/VERSION")
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
