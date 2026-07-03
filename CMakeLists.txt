# VERSION CONTROL 
cmake_minimum_required(VERSION 3.15 FATAL_ERROR)
if(POLICY CMP0144)
  cmake_policy(SET CMP0144 NEW)
endif()
set(PROJECT_PYTHON_VERSION 3.12)
set(MATLAB_DEFAULT_RELEASE "R2023b")

#set(CMAKE_C_COMPILER gcc-11)
#set(CMAKE_CXX_COMPILER g++-11)
#set(CMAKE_CUDA_COMPILER nvcc)

# PROJECT DEFINITION
set(project_name "slam-primitives")

# Set install default directory if not specified
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX ${CMAKE_SOURCE_DIR}/install CACHE PATH "Install path" FORCE)
endif()

# Major options
option(ENABLE_CUDA "Enable CUDA" OFF)
option(BUILD_SHARED_LIBS "Build libraries as shared" ON)
include(cmake/HandleOpenMP.cmake)

set(languages CXX)

if (ENABLE_CUDA)
  list(APPEND languages CUDA)
endif()

# Add cmake folder to path
list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

# Add git version handling
include(cmake/HandleGitVersion.cmake)

# Set version number
set(PROJECT_VERSION_MAJOR 0)
set(PROJECT_VERSION_MINOR 0)
set(PROJECT_VERSION_PATCH 0)
set(PROJECT_VERSION_PRERELEASE "")
set(PROJECT_VERSION_METADATA "")
set(PROJECT_VERSION_CORE "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}")

# Resolve version: git --> VERSION file --> hardcoded defaults above
resolve_project_version()

project( ${project_name} 
        LANGUAGES ${languages}
        VERSION ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH})

# Write VERSION file to the build directory by default. Writing into the source tree is opt-in so CI/test harness configures do not dirty the checkout.
option(WRITE_SOURCE_VERSION_FILE "Write VERSION into the source tree during CMake configure" OFF)

if(WRITE_SOURCE_VERSION_FILE)
  write_source_VERSION_file()
endif()

write_build_VERSION_file()
install(FILES "${PROJECT_BINARY_DIR}/VERSION" DESTINATION ".")

# Define variable for build as subproject (compare source dir)
set(BUILD_AS_MAIN_PROJECT ON)
if(NOT CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
  set(BUILD_AS_MAIN_PROJECT OFF)
endif()

# Define variable for namespacing (required to prevent global target clashes!)
set(LIB_NAMESPACE "${PROJECT_NAME}")
if (DEFINED LIB_NAMESPACE_OVERRIDE)
  set(LIB_NAMESPACE "${LIB_NAMESPACE_OVERRIDE}")
endif()
if (NOT DEFINED PROJECT_PYTHON_PACKAGE_NAME)
  string(REPLACE "-" "_" _default_python_package_name "${PROJECT_NAME}")
  set(PROJECT_PYTHON_PACKAGE_NAME "${_default_python_package_name}" CACHE STRING
      "Python package and extension module import name.")
endif()
set(CUDA_COMPILE_TARGET "${LIB_NAMESPACE}_cuda_compile_interface")
set(OPENGL_COMPILE_TARGET "${LIB_NAMESPACE}_opengl_compile_interface")
set(LIB_COMPILE_TARGET "${LIB_NAMESPACE}_lib_compile_interface")
set(SPDLOG_COMPILE_TARGET "${LIB_NAMESPACE}_spdlog_interface")
set(SANITIZER_TARGET "${LIB_NAMESPACE}_sanitizer_target_interface")
set(BUILD_PROGRAMS_OPTION_NAME "${LIB_NAMESPACE}_BUILD_PROGRAMS")
set(BUILD_EXAMPLES_OPTION_NAME "${LIB_NAMESPACE}_BUILD_EXAMPLES")

# Handle toolchain settings (after project so compiler/system vars are populated)
include(cmake/toolchains/HandleToolchain.cmake)

# Configure cmake targets
include(cmake/HandleCustomTargets.cmake)

# Add build type if not specified
if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "RelWithDebInfo" CACHE STRING "Build type (Debug, Release, RelWithDebInfo, MinSizeRel, NOPTIM)" FORCE)
endif()
string(TOLOWER "${CMAKE_BUILD_TYPE}" CMAKE_BUILD_TYPE_LOWER)

# Guard against in-source builds
if(${CMAKE_SOURCE_DIR} STREQUAL ${CMAKE_BINARY_DIR})
  message(FATAL_ERROR "In-source builds not allowed. Please make a new directory (called a build directory) and run CMake from there. You may need to remove CMakeCache.txt. ")
endif()

# Add GNU install dirs
include(GNUInstallDirs)

# Add cmake modules
include(ExternalProject)

# Add CUDA tools
include(cmake/HandleCUDA.cmake)
include(cmake/HandleTBB.cmake)

# Add handle of python
include(cmake/HandlePython.cmake)
if(BUILD_AS_MAIN_PROJECT)
  include(cmake/HandleWrapper.cmake)
endif()

# OPTIONS
option(ENABLE_TESTS              "Build and run tests" ON)
option(ENABLE_PYTHON_TESTS       "Discover and register Python pytest tests through CTest" OFF)
option(ENABLE_FETCH_CATCH2 "Fetch Catch2 from GitHub if not found" ON)
option(ENABLE_SPDLOG "Enable spdlog logging support" OFF)
option(ENABLE_FETCH_SPDLOG "Fetch spdlog from GitHub if not found" OFF)

# Catch2 tests configuration
set(CATCH2_TEST_REPORTER "compact" CACHE STRING "Catch2 reporter used by catch_discover_tests. Set empty to use Catch2 defaults.")
set(CATCH2_TEST_PROPERTIES "LABELS;catch2" CACHE STRING "CTest property name/value pairs applied to discovered Catch2 tests.")

# Options for building programs and examples when this project is the main
option(${BUILD_PROGRAMS_OPTION_NAME} "Build project program targets when this project is the main project" ON)
option(${BUILD_EXAMPLES_OPTION_NAME} "Build project example targets when this project is the main project" ON)
option(VERBOSE "Verbose output" OFF) # Defines VERBOSE flag in code if set to ON

if(BUILD_AS_MAIN_PROJECT AND ENABLE_TESTS)
  include(CTest)
endif()

if (NOT DEFINED GTWRAP_BUILD_PYTHON_DEFAULT)
  set(GTWRAP_BUILD_PYTHON_DEFAULT OFF CACHE BOOL "Default Python wrapper setting for all subprojects")
endif()
if (NOT DEFINED GTWRAP_BUILD_MATLAB_DEFAULT)
  set(GTWRAP_BUILD_MATLAB_DEFAULT OFF CACHE BOOL "Default MATLAB wrapper setting for all subprojects")
endif()

set(GTWRAP_PYTHON_OPTION_NAME "${LIB_NAMESPACE}_BUILD_PYTHON_WRAPPER")
set(GTWRAP_MATLAB_OPTION_NAME "${LIB_NAMESPACE}_BUILD_MATLAB_WRAPPER")
set(GTWRAP_INTERFACE_OPTION_NAME "${LIB_NAMESPACE}_WRAPPER_INTERFACE_FILES")
set(GTWRAP_TOP_NAMESPACE_OPTION_NAME "${LIB_NAMESPACE}_GTWRAP_TOP_NAMESPACE")
set(GTWRAP_DEPENDENCIES_OPTION_NAME "${LIB_NAMESPACE}_GTWRAP_DEPENDENCY_TARGETS")
set(GTWRAP_ROOT_OPTION_NAME "${LIB_NAMESPACE}_GTWRAP_ROOT_DIR")

option(${GTWRAP_PYTHON_OPTION_NAME} "Build Python wrapper" ${GTWRAP_BUILD_PYTHON_DEFAULT})
option(${GTWRAP_MATLAB_OPTION_NAME} "Build MATLAB wrapper" ${GTWRAP_BUILD_MATLAB_DEFAULT})

if (NOT DEFINED ${GTWRAP_INTERFACE_OPTION_NAME})
  set(${GTWRAP_INTERFACE_OPTION_NAME}
      "${CMAKE_CURRENT_SOURCE_DIR}/src/slam_primitives/wrapped/slam_primitives_wrapper.i"
      CACHE STRING
      "Ordered list of gtwrap interface files (.i). First entry is the top-level module file."
      FORCE)
endif()

if (NOT DEFINED ${GTWRAP_TOP_NAMESPACE_OPTION_NAME})
  set(${GTWRAP_TOP_NAMESPACE_OPTION_NAME}
      "slam_primitives"
      CACHE STRING
      "Top namespace used for gtwrap code generation."
      FORCE)
endif()

if (NOT DEFINED ${GTWRAP_DEPENDENCIES_OPTION_NAME})
  set(${GTWRAP_DEPENDENCIES_OPTION_NAME}
      ""
      CACHE STRING
      "Additional dependency targets required before wrapping."
      FORCE)
endif()

if (NOT DEFINED ${GTWRAP_ROOT_OPTION_NAME})
  set(${GTWRAP_ROOT_OPTION_NAME}
      ""
      CACHE PATH
      "Optional path to local wrap checkout root (contains cmake/PybindWrap.cmake)."
      FORCE)
endif()

option(NO_OPTIMIZATION "Disable optimization flags" OFF)
option(WARNINGS_ARE_ERRORS "Treat warnings as errors" OFF)
option(SANITIZE_BUILD "Enable sanitizers in build" OFF)
set(SANITIZERS "address,undefined,leak" CACHE STRING "Sanitizers to enable when SANITIZE_BUILD is ON (comma-separated)")
option(ENABLE_TBB "Enable Intel oneTBB support" OFF)
option(CPU_ENABLE_NATIVE_TUNING "Enable -march=native -mtune=native for GNU/Clang in optimized builds" ON)
option(CPU_ENABLE_FMA "Enable CPU FMA instructions (-mfma) for GNU/Clang in optimized builds" OFF)
option(CPU_ENABLE_SIMD "Enable explicit SIMD ISA flags for GNU/Clang in optimized builds" OFF)
set(CPU_SIMD_LEVEL "native" CACHE STRING "SIMD ISA when CPU_ENABLE_SIMD=ON: native,sse4.2,avx,avx2,avx512f")
set_property(CACHE CPU_SIMD_LEVEL PROPERTY STRINGS native sse4.2 avx avx2 avx512f)
set(CPU_EXTRA_OPT_FLAGS "" CACHE STRING "Extra CPU optimization flags for GNU/Clang optimized builds")
option(CUDA_ENABLE_FMAD "Enable fused multiply-add contraction in NVCC (--fmad=true)" ON)
option(CUDA_ENABLE_EXTRA_DEVICE_VECTORIZATION "Enable NVCC extra device vectorization" OFF)
option(CUDA_USE_FAST_MATH "Enable NVCC fast math in regular CUDA compilation" OFF)
set(CUDA_NVCC_EXTRA_FLAGS "" CACHE STRING "Extra flags passed to NVCC for CUDA compilation")
set(EXTRA_C_FLAGS "" CACHE STRING "Extra C compiler flags appended to project-managed flags")
set(EXTRA_CXX_FLAGS "" CACHE STRING "Extra C++ compiler flags appended to project-managed flags")
set(PYTHON_EXECUTABLE "python3") # Specify the Python executable to use

include(cmake/HandleCompilerFlags.cmake)
handle_compiler_flags(CXX_STANDARD 20)

# Handle OpenMP
handle_openmp()

# Handle sanitizers
include(cmake/HandleSanitizers.cmake)
handle_sanitizers()

# Handle profiling support
include(cmake/HandleProfiling.cmake)
option(PROFILING_PROPAGATES_TO_CONSUMERS "Propagate profiling interface flags/definitions to targets consuming the project library" OFF)
set(PROFILING_COMPILE_TARGET "${LIB_NAMESPACE}_profiling_interface")
handle_profiling(TARGET ${PROFILING_COMPILE_TARGET})

if (WARNINGS_ARE_ERRORS)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Werror")
    message(WARNING "ACHTUNG! Warnings will be treated treated as errors.")
endif()

message(STATUS "==============================================================")
message(STATUS "====================  Dependencies ===========================")

# LIBRARY DEPENDENCIES DEFINITION
find_package( Eigen3 3.4 REQUIRED )
find_package( Doxygen QUIET)

# Handle Catch2 tools
include(cmake/HandleCatch2.cmake)
include(cmake/HandleSpdlog.cmake)
handle_spdlog(TARGET ${SPDLOG_COMPILE_TARGET})

# Include cmake tools (depends on Catch2)
include(cmake/cmake_utils.cmake)

# Configure CUDA (creates interface target even when disabled)
handle_cuda(TARGET ${CUDA_COMPILE_TARGET} 
            MIN_VERSION 12.0)

# Handle OpenGL (creates interface targets even when disabled)
include(cmake/HandleOpenGL.cmake)
handle_opengl(TARGET ${OPENGL_COMPILE_TARGET})

# Add submodules if any found
include(cmake/HandleSubmodules.cmake)
handle_submodules() # Automatically adds subdirectories in lib/ (and build them if CMakeLists.txt found)

# Set the dependencies for the automated export
set(EXPORT_TARGET_DEPS Eigen3) # TODO make automatic based on used packages

if(ENABLE_CUDA)
  list(APPEND EXPORT_TARGET_DEPS CUDAToolkit)
endif()
if (ENABLE_OPENGL)
  list(APPEND EXPORT_TARGET_DEPS OpenGL::GL)
endif()
if(ENABLE_TBB)
  list(APPEND EXPORT_TARGET_DEPS TBB)
endif()
if(SPDLOG_ENABLED AND SPDLOG_EXTERNAL_PACKAGE)
  list(APPEND EXPORT_TARGET_DEPS spdlog)
endif()

message(STATUS "Target dependencies: ${EXPORT_TARGET_DEPS}")

#find_package( GTSAM 4.0 REQUIRED )
#find_package( GTSAM_UNSTABLE REQUIRED)
#find_package( sopengv )
#find_package( OpenCV core imgproc highgui features2d calib3d video)
#find_package( DBoW2 )
#find_package( Pangolin )
#find_package( jsoncpp )
#find_package( rapid_yaml)

# Interface target for C++ flags
add_library(${LIB_COMPILE_TARGET} INTERFACE)
handle_tbb(TARGET ${LIB_COMPILE_TARGET})
handle_compiler_flags_interface(TARGET ${LIB_COMPILE_TARGET})

# Add catch2 for unit testing
find_package(OpenCV QUIET)

# Create the installation target list 
set(installable_targets)

# TIP: To set target compilation options (or any other thing) that must be specific for a target or propagated, use the following cmake pattern (example). Requires cmake 3.15 or later. Here flag BUILD_INTERFACE regulates whether the compile flags are added to the target_compile_options. If true, they are added.
#add_library(library_compile_flags INTERFACE)
#target_compile_options(library_compile_flags INTERFACE 
#"$<${gcc_like_cxx}: $<BUILD_INTERFACE: -Wall;-Wextra;-Wshadow;-Wformat=2;-Wunused>>")
#target_link_libraries(library_target PUBLIC any_other_target library_compile_flags)

# Define include target interface
add_library(${project_name}_include INTERFACE)

# Define include directories for install compatibility
target_include_directories(${project_name}_include INTERFACE 
                           $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>  # Used during development
                           #$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/lib/stb_PeterCdev>  
                           #$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/lib/rapidyaml_PeterCdev>
                           #$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/lib/gdt>
                           #$<BUILD_INTERFACE:${CUDA_INCLUDE_DIRS}> 
                           #$<BUILD_INTERFACE:${OpenCV_INCLUDE_DIRS}>  # Add OpenCV include directories
                           $<INSTALL_INTERFACE:include/${project_name}>  # Used in installed projects
)

# Build/install tree for runtime programs: $ORIGIN/../lib
target_link_options(${project_name}_include INTERFACE
                    $<$<PLATFORM_ID:Linux>:-Wl,-rpath,\$ORIGIN/../lib>
                  )

# Install-tree exes look next to themselves
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH ON)

# Add libraries subdirectories if needed
include_directories( lib/header_only ) # tclap, fast_obj, stb image, rapidyaml, rapidjson

message(STATUS "===================================================================")
message(STATUS "====================  Library composition  ========================")

# Add library
add_subdirectory( src )

# Add examples to build
if (BUILD_AS_MAIN_PROJECT AND ${${BUILD_EXAMPLES_OPTION_NAME}})
  add_subdirectory( examples )
endif()

# Add tests to build
if (ENABLE_TESTS AND BUILD_AS_MAIN_PROJECT)
  add_subdirectory( tests )
endif()

# Add documentation
if (BUILD_AS_MAIN_PROJECT)
  set(DOC_SUBDIRS "${CMAKE_SOURCE_DIR}/src")
  if (DOXYGEN_FOUND)
      add_subdirectory( "doc" )
  else()
      message(STATUS "Doxygen not found. Skipping building documentation.")
  endif()
endif()

###########################################################################
### WRAPPERS CONFIGURATION
set(ANY_WRAPPER_ENABLED OFF)
if(BUILD_AS_MAIN_PROJECT)
  set(LIBNAME_WRAP_TARGET ${project_name})
  handle_gtwrappers() # You may also pass WRAP_INTERFACE_FILES variable to specify interface files, else autofetching is used
  handle_pybind11_wrapper()

  # Determine if any wrapper is enabled
  if (${GTWRAP_PYTHON_OPTION_NAME} OR PYBIND11_WRAPPER_ENABLED OR ${GTWRAP_MATLAB_OPTION_NAME})
    set(ANY_WRAPPER_ENABLED ON)
  endif()
endif()

###########################################################################
# INFO SECTION
# Print configuration variables
message(STATUS "===============================================================")
message(STATUS "================  Configuration Options  ======================")
# Project info
message(STATUS "CMAKE_VERSION                             : ${CMAKE_VERSION}")
message(STATUS "LIBRARY NAME                              : ${project_name}")
message(STATUS "LIBRARY TARGET TYPE                       : ${PROJECT_LIBRARY_KIND}")
message(STATUS "CROSS COMPILING                           : ${CMAKE_CROSSCOMPILING}")
message(STATUS "HOST SYSTEM                               : ${CMAKE_HOST_SYSTEM}")
message(STATUS "TARGET SYSTEM                             : ${CMAKE_SYSTEM}")
message(STATUS "TARGET ARCHITECTURE                       : ${CMAKE_SYSTEM_PROCESSOR}")
# CXX compiler
message(STATUS "CMAKE_CXX_COMPILER                        : ${CMAKE_CXX_COMPILER}")
message(STATUS "CMAKE_CXX_COMPILER_ID type                : ${CMAKE_CXX_COMPILER_ID}")
message(STATUS "CMAKE_CXX_COMPILER_VERSION                : ${CMAKE_CXX_COMPILER_VERSION}")

# CUDA arch and compiler
if (ENABLE_CUDA)
  message(STATUS "CUDA enabled                             : ${ENABLE_CUDA}")
  message(STATUS "CUDA architecture                        : ${cuda_arch}")
  message(STATUS "CUDA architecture sm version             : ${sm_version}")
  message(STATUS "CMAKE_CUDA_COMPILER                      : ${CMAKE_CUDA_COMPILER}")
  message(STATUS "CMAKE_CUDA_COMPILER_ID type              : ${CMAKE_CUDA_COMPILER_ID}")
  message(STATUS "CMAKE_CUDA_COMPILER_VERSION              : ${CMAKE_CUDA_COMPILER_VERSION}")
  message(STATUS "CUDA FMAD                                : ${CUDA_ENABLE_FMAD}")
  message(STATUS "CUDA extra device vectorization          : ${CUDA_ENABLE_EXTRA_DEVICE_VECTORIZATION}")
  message(STATUS "CUDA fast math (regular compile)         : ${CUDA_USE_FAST_MATH}")
  message(STATUS "CUDA extra NVCC flags                    : ${CUDA_NVCC_EXTRA_FLAGS}")
endif()
message(STATUS "TBB enabled                              : ${ENABLE_TBB}")
message(STATUS "CPU native tuning                        : ${CPU_ENABLE_NATIVE_TUNING}")
message(STATUS "CPU SIMD enabled                         : ${CPU_ENABLE_SIMD}")
message(STATUS "CPU SIMD level                           : ${CPU_SIMD_LEVEL}")
message(STATUS "CPU FMA                                  : ${CPU_ENABLE_FMA}")
message(STATUS "CPU extra optimization flags             : ${CPU_EXTRA_OPT_FLAGS}")
message(STATUS "Project extra C flags                    : ${EXTRA_C_FLAGS}")
message(STATUS "Project extra C++ flags                  : ${EXTRA_CXX_FLAGS}")
message(STATUS "OpenCV found                             : ${OpenCV_FOUND}")

# Installation
message(STATUS "CMAKE_INSTALL_PREFIX                      : ${CMAKE_INSTALL_PREFIX}")
message(STATUS "CMAKE_INSTALL_LIBDIR                      : ${CMAKE_INSTALL_LIBDIR}")
message(STATUS "CMAKE_INSTALL_INCLUDEDIR                  : ${CMAKE_INSTALL_INCLUDEDIR}")
message(STATUS "CMAKE_INSTALL_BINDIR                      : ${CMAKE_INSTALL_BINDIR}")
message(STATUS "BUILD_SHARED_LIBS                         : ${BUILD_SHARED_LIBS}")

# Build type
if(NOT MSVC AND NOT XCODE_VERSION)
  message(STATUS "Build type                                : ${CMAKE_BUILD_TYPE}")  
  message(STATUS "Optimization override:                    : ${NO_OPTIMIZATION}")  

  print_compiler_flags_summary()
endif()
# Print info about wrappers if any
if (ANY_WRAPPER_ENABLED)
  message(STATUS "================  Wrappers Configuration  ======================")
  message(STATUS "Python pybind11 direct wrapper              : ${PYBIND11_WRAPPER_ENABLED}")
  message(STATUS "Python gtwrapper                            : ${${GTWRAP_PYTHON_OPTION_NAME}}")
  message(STATUS "MATLAB gtwrapper                            : ${${GTWRAP_MATLAB_OPTION_NAME}}")
  message(STATUS "MATLAB default release                      : ${MATLAB_DEFAULT_RELEASE}")
  message(STATUS "Python executable                           : ${PYTHON_EXECUTABLE}")
  message(STATUS "Python version                              : ${PROJECT_PYTHON_VERSION}")
  message(STATUS "gtwrap interface option name                : ${GTWRAP_INTERFACE_OPTION_NAME}")
  message(STATUS "gtwrap interface files                      : ${${GTWRAP_INTERFACE_OPTION_NAME}}")
  message(STATUS "gtwrap top namespace                        : ${${GTWRAP_TOP_NAMESPACE_OPTION_NAME}}")
  message(STATUS "gtwrap root override                        : ${${GTWRAP_ROOT_OPTION_NAME}}")
endif()
message(STATUS "===============================================================")

# AUXILIARY 
# Set dashboard properties (needed for CDash)
set(CTEST_PROJECT_NAME ${project_name})
set(CTEST_NIGHTLY_START_TIME "00:00:00 CET")

# Set the dashboard drop method and location
#set(CTEST_DROP_METHOD "http")
#set(CTEST_DROP_SITE "my.cdash.org")
#set(CTEST_DROP_LOCATION "/submit.php?project=CMakeTutorial")
#set(CTEST_DROP_SITE_CDASH TRUE)

# PACKAGING CONFIGURATION 
include(InstallRequiredSystemLibraries)
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_PACKAGE_VERSION_MAJOR "${PROJECT_VERSION_MAJOR}")
set(CPACK_PACKAGE_VERSION_MINOR "${PROJECT_VERSION_MINOR}")
set(CPACK_PACKAGE_VERSION_PATCH "${PROJECT_VERSION_PATCH}")
if(DEFINED FULL_VERSION AND NOT "${FULL_VERSION}" STREQUAL "")
  set(CPACK_PACKAGE_FILE_NAME "${project_name}-${FULL_VERSION}")
  set(CPACK_SOURCE_PACKAGE_FILE_NAME "${project_name}-${FULL_VERSION}")
endif()
set(CPACK_GENERATOR "TGZ")
set(CPACK_SOURCE_GENERATOR "TGZ")
include(CPack)
