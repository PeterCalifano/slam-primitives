# CMake configuration to handle OpenGL setup and linking
include_guard(GLOBAL)
include(CMakeParseArguments)

if (NOT DEFINED ENABLE_OPENGL)
    option(ENABLE_OPENGL "Enable OpenGL" OFF)
endif()

function(handle_opengl)

    # Add options
    set(options REQUIRED)
    set(oneValueArgs TARGET)
    set(multiValueArgs LIBRARIES)
    cmake_parse_arguments(HGL "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Add target if not provided
    if(NOT HGL_TARGET)
        set(HGL_TARGET opengl_compile_interface)
    endif()
    if(NOT TARGET ${HGL_TARGET})
        add_library(${HGL_TARGET} INTERFACE)
    endif()

    set(OPENGL_FOUND OFF PARENT_SCOPE)
    set(OPENGL_LIBRARIES "" PARENT_SCOPE)
    set(OPENGL_INCLUDE_DIRS "" PARENT_SCOPE)

    if(NOT ENABLE_OPENGL)
        return() # Return if OpenGL not enabled
    endif()

    # Look for OpenGL
    if(HGL_REQUIRED)
        find_package(OpenGL REQUIRED)
    else()
        find_package(OpenGL)
    endif()

    if(NOT OpenGL_FOUND)
        if(HGL_REQUIRED)
            message(FATAL_ERROR "OpenGL requested but not found.")
        endif()
        return()
    endif()

    # Link libraries and include directories
    if(HGL_LIBRARIES)
        target_link_libraries(${HGL_TARGET} INTERFACE ${HGL_LIBRARIES})
    elseif(TARGET OpenGL::OpenGL)
        target_link_libraries(${HGL_TARGET} INTERFACE OpenGL::OpenGL)
    elseif(TARGET OpenGL::GL)
        target_link_libraries(${HGL_TARGET} INTERFACE OpenGL::GL)
    elseif(OPENGL_LIBRARIES)
        target_link_libraries(${HGL_TARGET} INTERFACE ${OPENGL_LIBRARIES})
    endif()

    if(OPENGL_INCLUDE_DIR)
        target_include_directories(${HGL_TARGET} INTERFACE ${OPENGL_INCLUDE_DIR})
    elseif(OPENGL_INCLUDE_DIRS)
        target_include_directories(${HGL_TARGET} INTERFACE ${OPENGL_INCLUDE_DIRS})
    endif()

    target_compile_definitions(${HGL_TARGET} INTERFACE __OPENGL_ENABLED__=1)

    set(OPENGL_FOUND ON PARENT_SCOPE)
    set(OPENGL_LIBRARIES "${OPENGL_LIBRARIES}" PARENT_SCOPE)
    set(OPENGL_INCLUDE_DIRS "${OPENGL_INCLUDE_DIRS}" PARENT_SCOPE)

    message(STATUS "OpenGL enabled")
endfunction()
