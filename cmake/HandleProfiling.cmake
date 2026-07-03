# CMake configuration for profiling support.
#
# gperftools detection and linking is opt-in. Detection uses PkgConfig hints
# (respects custom prefixes / .pc files) and the GPERFTOOLS_ROOT environment
# variable, then falls back to CMake's standard system search.
#
# When ENABLE_PROFILING=ON:
#   - Adds -fno-omit-frame-pointer so perf/callgrind/gperftools produce useful call stacks
#   - Adds -fno-inline-functions to prevent inlining from obscuring call graphs
#   - Enables libprofiler detection/linking by default through ENABLE_GPERFTOOLS
#   - Detects Valgrind client headers and exposes them when found (zero overhead at runtime).
#     Defines VALGRIND_ANNOTATIONS_ENABLED when available; use with valgrind/callgrind.h etc.
#
# ENABLE_TCMALLOC=ON is separate and defaults OFF. This prevents MATLAB MEX
# targets from inheriting tcmalloc in normal wrapper builds.
#
# ACHTUNG! -fno-omit-frame-pointer applies to all build types including Release.
# Runtime overhead is ~1% but is required for accurate stack unwinding.
#
# To override detection, set in CMake cache before configuring:
#   GPERFTOOLS_INCLUDE_DIR   - path to gperftools/profiler.h
#   GPERFTOOLS_PROFILER_LIBRARY  - full path to libprofiler
#   GPERFTOOLS_TCMALLOC_LIBRARY  - full path to libtcmalloc / libtcmalloc_minimal
# Or set the GPERFTOOLS_ROOT environment variable to an installation prefix.

include_guard(GLOBAL)

option(ENABLE_PROFILING "Enable profiling-friendly build flags and valgrind detection" OFF)
option(ENABLE_GPERFTOOLS "Enable gperftools libprofiler detection/linking" ${ENABLE_PROFILING})
option(ENABLE_TCMALLOC "Enable gperftools tcmalloc detection/linking" OFF)

function(handle_profiling)
    cmake_parse_arguments(PROF "" "TARGET" "" ${ARGN})

    if(NOT DEFINED PROF_TARGET)
        if(DEFINED LIB_NAMESPACE)
            set(PROF_TARGET "${LIB_NAMESPACE}_profiling_interface")
        else()
            set(PROF_TARGET "profiling_interface")
        endif()
    endif()

    if(TARGET ${PROF_TARGET})
        return()
    endif()

    add_library(${PROF_TARGET} INTERFACE)

    # -------------------------------------------------------------------------
    # gperftools detection. Priority:
    # cache override > GPERFTOOLS_ROOT env > PkgConfig hints > system.
    # -------------------------------------------------------------------------

    # Collect hints from PkgConfig (honours custom prefix paths / .pc files).
    set(_gperf_lib_hints "")
    set(_gperf_inc_hints "")

    if(ENABLE_GPERFTOOLS OR ENABLE_TCMALLOC)
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            if(ENABLE_GPERFTOOLS)
                pkg_check_modules(_PC_PROFILER QUIET libprofiler)
                if(_PC_PROFILER_FOUND)
                    list(APPEND _gperf_lib_hints ${_PC_PROFILER_LIBRARY_DIRS})
                    list(APPEND _gperf_inc_hints ${_PC_PROFILER_INCLUDE_DIRS})
                endif()
            endif()
            if(ENABLE_TCMALLOC)
                pkg_check_modules(_PC_TCMALLOC QUIET libtcmalloc)
                if(_PC_TCMALLOC_FOUND)
                    list(APPEND _gperf_lib_hints ${_PC_TCMALLOC_LIBRARY_DIRS})
                    list(APPEND _gperf_inc_hints ${_PC_TCMALLOC_INCLUDE_DIRS})
                endif()
            endif()
        endif()

        # GPERFTOOLS_ROOT env var (prepend so it wins over system paths).
        if(DEFINED ENV{GPERFTOOLS_ROOT})
            list(PREPEND _gperf_lib_hints "$ENV{GPERFTOOLS_ROOT}/lib"
                                          "$ENV{GPERFTOOLS_ROOT}/lib64")
            list(PREPEND _gperf_inc_hints "$ENV{GPERFTOOLS_ROOT}/include")
        endif()

        # find_path / find_library: HINTS are searched before system paths.
        # CMake's built-in system search already covers arch-specific lib dirs
        # (/usr/lib/x86_64-linux-gnu, /usr/lib/aarch64-linux-gnu, etc.).
        find_path(GPERFTOOLS_INCLUDE_DIR
            NAMES gperftools/profiler.h google/profiler.h
            HINTS ${_gperf_inc_hints}
            DOC "gperftools include directory"
        )
    endif()

    if(ENABLE_GPERFTOOLS)
        find_library(GPERFTOOLS_PROFILER_LIBRARY
            NAMES profiler
            HINTS ${_gperf_lib_hints}
            DOC "gperftools libprofiler"
        )
    endif()

    if(ENABLE_TCMALLOC)
        find_library(GPERFTOOLS_TCMALLOC_LIBRARY
            NAMES tcmalloc tcmalloc_minimal
            HINTS ${_gperf_lib_hints}
            DOC "gperftools libtcmalloc / libtcmalloc_minimal"
        )
    endif()

    # -------------------------------------------------------------------------
    # Link requested gperftools components.
    # -------------------------------------------------------------------------
    if(ENABLE_GPERFTOOLS AND GPERFTOOLS_PROFILER_LIBRARY)
        message(STATUS "  gperftools libprofiler : ${GPERFTOOLS_PROFILER_LIBRARY}")
        target_link_libraries(${PROF_TARGET} INTERFACE ${GPERFTOOLS_PROFILER_LIBRARY})
        target_compile_definitions(${PROF_TARGET} INTERFACE PROFILING_GPERFTOOLS_ENABLED)
        if(GPERFTOOLS_INCLUDE_DIR)
            target_include_directories(${PROF_TARGET} INTERFACE ${GPERFTOOLS_INCLUDE_DIR})
        endif()
    elseif(ENABLE_GPERFTOOLS)
        message(STATUS "  gperftools libprofiler : not found (install libgoogle-perftools-dev)")
    else()
        message(STATUS "  gperftools libprofiler : OFF (set ENABLE_GPERFTOOLS=ON or ENABLE_PROFILING=ON)")
    endif()

    if(ENABLE_TCMALLOC AND GPERFTOOLS_TCMALLOC_LIBRARY)
        message(STATUS "  gperftools libtcmalloc : ${GPERFTOOLS_TCMALLOC_LIBRARY}")
        target_link_libraries(${PROF_TARGET} INTERFACE ${GPERFTOOLS_TCMALLOC_LIBRARY})
        target_compile_definitions(${PROF_TARGET} INTERFACE PROFILING_TCMALLOC_ENABLED)
        if(GPERFTOOLS_INCLUDE_DIR)
            target_include_directories(${PROF_TARGET} INTERFACE ${GPERFTOOLS_INCLUDE_DIR})
        endif()
    elseif(ENABLE_TCMALLOC)
        message(FATAL_ERROR "ENABLE_TCMALLOC=ON but libtcmalloc was not found")
    else()
        message(STATUS "  gperftools libtcmalloc : OFF (set ENABLE_TCMALLOC=ON to enable)")
    endif()

    # -------------------------------------------------------------------------
    # Profiling flags and annotations — only when ENABLE_PROFILING=ON.
    # -------------------------------------------------------------------------
    if(NOT ENABLE_PROFILING)
        message(STATUS "Profiling flags/annotations: OFF (set ENABLE_PROFILING=ON to enable)")
        set(PROFILING_TARGET ${PROF_TARGET} PARENT_SCOPE)
        return()
    endif()

    message(STATUS "Profiling flags/annotations: ON")

    # Required for accurate profiler stack unwinding.
    target_compile_options(${PROF_TARGET} INTERFACE
        -fno-omit-frame-pointer
        -fno-inline-functions
    )

    # Valgrind client headers (zero runtime overhead when not running under Valgrind).
    # Exposes valgrind/callgrind.h, valgrind/memcheck.h for source annotations.
    find_path(VALGRIND_INCLUDE_DIR
        NAMES valgrind/valgrind.h
        HINTS ${_gperf_inc_hints}
        DOC "Valgrind client headers"
    )

    if(VALGRIND_INCLUDE_DIR)
        message(STATUS "  Valgrind headers       : ${VALGRIND_INCLUDE_DIR} (VALGRIND_ANNOTATIONS_ENABLED)")
        target_include_directories(${PROF_TARGET} INTERFACE ${VALGRIND_INCLUDE_DIR})
        target_compile_definitions(${PROF_TARGET} INTERFACE VALGRIND_ANNOTATIONS_ENABLED)
    else()
        message(STATUS "  Valgrind headers       : not found (install valgrind)")
    endif()

    set(PROFILING_TARGET ${PROF_TARGET} PARENT_SCOPE)
endfunction()
