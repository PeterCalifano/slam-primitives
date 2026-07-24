cmake_minimum_required(VERSION 3.16)

project(slam_primitives_colcon_shim LANGUAGES NONE)

get_filename_component(
  SLAM_PRIMITIVES_REPOSITORY_ROOT
  "${CMAKE_CURRENT_LIST_DIR}/../.."
  ABSOLUTE)

option(
  SLAM_PRIMITIVES_ENABLE_CUDA
  "Enable optional CUDA support in the slam-primitives core."
  OFF)

set(ENABLE_CUDA "${SLAM_PRIMITIVES_ENABLE_CUDA}" CACHE BOOL
    "Enable CUDA support in the core library." FORCE)
set(ENABLE_TESTS OFF CACHE BOOL
    "Disable core Catch2 tests in the ROS 2 overlay." FORCE)
set(ENABLE_FETCH_CATCH2 OFF CACHE BOOL
    "Do not fetch Catch2 while building the ROS 2 overlay." FORCE)
set(ENABLE_OPENGL OFF CACHE BOOL
    "Keep the core ROS overlay independent of OpenGL." FORCE)
set(GTWRAP_BUILD_PYTHON_DEFAULT OFF CACHE BOOL
    "Disable Python wrapper generation in the ROS 2 overlay." FORCE)
set(GTWRAP_BUILD_MATLAB_DEFAULT OFF CACHE BOOL
    "Disable MATLAB wrapper generation in the ROS 2 overlay." FORCE)
set(slam-primitives_BUILD_PROGRAMS OFF CACHE BOOL
    "Disable standalone programs in the ROS 2 overlay." FORCE)
set(slam-primitives_BUILD_EXAMPLES OFF CACHE BOOL
    "Disable standalone examples in the ROS 2 overlay." FORCE)

add_subdirectory(
  "${SLAM_PRIMITIVES_REPOSITORY_ROOT}"
  "${CMAKE_CURRENT_BINARY_DIR}/slam_primitives_core")
