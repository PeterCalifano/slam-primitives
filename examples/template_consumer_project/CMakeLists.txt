# VERSION CONTROL 
cmake_minimum_required(VERSION 3.15 FATAL_ERROR)

#set(CMAKE_C_COMPILER gcc-11)
#set(CMAKE_CXX_COMPILER g++-11)
#set(CMAKE_CUDA_COMPILER nvcc)

# PROJECT DEFINITION
set(project_name "example_consumer_project")
option(BUILD_SHARED_LIBS "Build libraries as shared" ON)

# Assumes one has built slam-primitives with install in the root
set(DEPENDENCY_ROOT_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/../../")
set(SLAM_PRIMITIVES_INSTALL_PREFIX "${DEPENDENCY_ROOT_PREFIX}/install"
    CACHE PATH "slam-primitives install prefix to consume")

if(NOT EXISTS "${SLAM_PRIMITIVES_INSTALL_PREFIX}/lib/cmake/slam-primitives/slam-primitivesConfig.cmake")
    message(FATAL_ERROR
        "slam-primitives was not found at SLAM_PRIMITIVES_INSTALL_PREFIX='${SLAM_PRIMITIVES_INSTALL_PREFIX}'. "
        "Install slam-primitives first, or configure this example with "
        "-DSLAM_PRIMITIVES_INSTALL_PREFIX=/path/to/slam-primitives-install.")
endif()

project(${project_name} VERSION 0.1.0 LANGUAGES CXX)

# Tell cmake where to find slam-primitives
list(APPEND CMAKE_PREFIX_PATH "${SLAM_PRIMITIVES_INSTALL_PREFIX}")
find_package(slam-primitives REQUIRED CONFIG)

# Alternatives: 
# 1. find_package(slam-primitives REQUIRED CONFIG PATHS "${DEPENDENCY_ROOT_PREFIX}/install/lib/cmake/")
# 2. When configuring the project: cmake -DCMAKE_PREFIX_PATH=/path/to/slam-primitives_install (...)
# 3. Set CMAKE_PREFIX_PATH in the environment: export CMAKE_PREFIX_PATH=/path/to/slam-primitives_install


# Add executable target
add_executable(${project_name} example_project.cpp)

# Link target
target_link_libraries(${project_name} PRIVATE slam-primitives::slam-primitives)

get_target_property(INC slam-primitives::slam-primitives INTERFACE_INCLUDE_DIRECTORIES)
message(STATUS "Include directories: ${INC}\n")
