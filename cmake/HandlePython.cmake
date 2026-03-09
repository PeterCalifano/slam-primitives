# CMake configuration to handle Python and MATLAB wrapper configuration
include_guard(GLOBAL)

include(CMakeParseArguments)

# Function to handle Python and MATLAB wrapper configuration
function(handle_python)
  set(one_value_args
      BUILD_PYTHON_VAR
      BUILD_MATLAB_VAR
      PYTHON_VERSION_VAR
      PYTHON_VERSION_DEFAULT
      PYTHON_INSTALL_PATH_VAR
      BUILD_UNSTABLE_VAR
      UNSTABLE_BUILD_PYTHON_VAR)
  cmake_parse_arguments(HP "" "${one_value_args}" "" ${ARGN})

  if(NOT HP_BUILD_PYTHON_VAR AND NOT HP_BUILD_MATLAB_VAR)
    message(FATAL_ERROR "handle_python requires BUILD_PYTHON_VAR or BUILD_MATLAB_VAR.")
  endif()

  # Local variables to track whether to build python/matlab
  set(_build_python OFF)
  set(_build_matlab OFF)

  if(HP_BUILD_PYTHON_VAR AND DEFINED ${HP_BUILD_PYTHON_VAR})
    set(_build_python ${${HP_BUILD_PYTHON_VAR}})
  endif()
  if(HP_BUILD_MATLAB_VAR AND DEFINED ${HP_BUILD_MATLAB_VAR})
    set(_build_matlab ${${HP_BUILD_MATLAB_VAR}})
  endif()

  if(NOT _build_python AND NOT _build_matlab)
    return()
  endif()

  # Determine requested python version
  if(HP_PYTHON_VERSION_VAR)
    if(NOT DEFINED ${HP_PYTHON_VERSION_VAR})
      if(HP_PYTHON_VERSION_DEFAULT)
        set(${HP_PYTHON_VERSION_VAR} "${HP_PYTHON_VERSION_DEFAULT}" CACHE STRING
            "The version of Python to build the wrappers against." FORCE)
      else()
        set(${HP_PYTHON_VERSION_VAR} "Default" CACHE STRING
            "The version of Python to build the wrappers against." FORCE)
      endif()
    endif()
    set(_requested_python_version "${${HP_PYTHON_VERSION_VAR}}")
  else()
    set(_requested_python_version "Default")
  endif()

  # Find python interpreter
  if(CMAKE_VERSION VERSION_LESS "3.12.0") # For cmake versions < 3.12, use PythonInterp and PythonLibs
    if(NOT _requested_python_version STREQUAL "Default")
      find_package(PythonInterp ${_requested_python_version})
    else()
      find_package(PythonInterp)
    endif()

    if(NOT PYTHONINTERP_FOUND)
      message(
        FATAL_ERROR
          "Cannot find Python interpreter. Please install Python >= 3.6.")
    endif()

    # Find Python libraries
    if(PYTHON_VERSION_STRING)
      find_package(PythonLibs ${PYTHON_VERSION_STRING})
    else()
      find_package(PythonLibs)
    endif()

    set(Python_VERSION_MAJOR ${PYTHON_VERSION_MAJOR})
    set(Python_VERSION_MINOR ${PYTHON_VERSION_MINOR})
    set(Python_VERSION_PATCH ${PYTHON_VERSION_PATCH})
    set(Python_EXECUTABLE ${PYTHON_EXECUTABLE})
  
  else()
    # For cmake versions >= 3.12, use Python3 package
    if(NOT _requested_python_version STREQUAL "Default")
      find_package(Python3 ${_requested_python_version} COMPONENTS Interpreter Development)
    else()
      find_package(Python3 COMPONENTS Interpreter Development)
    endif()

    if(NOT Python3_FOUND)
      message(
        FATAL_ERROR
          "Cannot find Python3 interpreter. Please install Python >= 3.6.")
    endif()

    set(Python_VERSION_MAJOR ${Python3_VERSION_MAJOR})
    set(Python_VERSION_MINOR ${Python3_VERSION_MINOR})
    set(Python_VERSION_PATCH ${Python3_VERSION_PATCH})
    set(Python_EXECUTABLE ${Python3_EXECUTABLE})
  endif()

  # Set the python version variable if requested and set to Default
  if(HP_PYTHON_VERSION_VAR AND _requested_python_version STREQUAL "Default")
    set(${HP_PYTHON_VERSION_VAR}
        "${Python_VERSION_MAJOR}.${Python_VERSION_MINOR}.${Python_VERSION_PATCH}"
        CACHE STRING "The version of Python to build the wrappers against."
              FORCE)
  endif()

  message(STATUS "Using Python executable: ${Python_EXECUTABLE}")
  
  if(_build_python)
    if(HP_UNSTABLE_BUILD_PYTHON_VAR AND DEFINED ${HP_UNSTABLE_BUILD_PYTHON_VAR}
       AND ${${HP_UNSTABLE_BUILD_PYTHON_VAR}})
      if(HP_BUILD_UNSTABLE_VAR AND DEFINED ${HP_BUILD_UNSTABLE_VAR}
         AND NOT ${${HP_BUILD_UNSTABLE_VAR}})
        message(WARNING "${HP_UNSTABLE_BUILD_PYTHON_VAR} requires the unstable module to be enabled.")
        set(${HP_UNSTABLE_BUILD_PYTHON_VAR} OFF CACHE BOOL
            "Build python wrappers for unstable modules." FORCE)
      endif()
    endif()

    if(HP_PYTHON_INSTALL_PATH_VAR AND NOT DEFINED ${HP_PYTHON_INSTALL_PATH_VAR})
      set(${HP_PYTHON_INSTALL_PATH_VAR} "${CMAKE_INSTALL_PREFIX}/python" CACHE PATH
          "Python wrapper install path." FORCE)
    endif()
  endif()
endfunction()

# Legacy inherited from GTSAM
if(DEFINED GTSAM_BUILD_PYTHON OR DEFINED GTSAM_INSTALL_MATLAB_TOOLBOX)
  handle_python(
    BUILD_PYTHON_VAR GTSAM_BUILD_PYTHON
    BUILD_MATLAB_VAR GTSAM_INSTALL_MATLAB_TOOLBOX
    PYTHON_VERSION_VAR GTSAM_PYTHON_VERSION
    PYTHON_VERSION_DEFAULT Default
    PYTHON_INSTALL_PATH_VAR GTSAM_PY_INSTALL_PATH
    BUILD_UNSTABLE_VAR GTSAM_BUILD_UNSTABLE
    UNSTABLE_BUILD_PYTHON_VAR GTSAM_UNSTABLE_BUILD_PYTHON)
endif()
