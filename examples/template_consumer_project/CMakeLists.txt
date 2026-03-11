# VERSION CONTROL 
cmake_minimum_required(VERSION 3.15 FATAL_ERROR)

#set(CMAKE_C_COMPILER gcc-11)
#set(CMAKE_CXX_COMPILER g++-11)
#set(CMAKE_CUDA_COMPILER nvcc)

# PROJECT DEFINITION
set(project_name "example_consumer_project")
option(BUILD_SHARED_LIBS "Build libraries as shared" ON)

# Assumes one has built the template_project with install in the root
set(DEPENDENCY_ROOT_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/../../")

# Check if it exists 
if (NOT EXISTS "${DEPENDENCY_ROOT_PREFIX}/install")
    # Build and install it
    execute_process(
        COMMAND bash -c "cd ${DEPENDENCY_ROOT_PREFIX} && cmake -S . -B build -DCMAKE_INSTALL_PREFIX=./install -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS} && cmake --build build --target install"
    )
endif()

if(NOT EXISTS "${DEPENDENCY_ROOT_PREFIX}/install/lib/cmake/")
    message(FATAL_ERROR "Please build and install the template_project first.")
endif()

project(${project_name} VERSION 0.1.0 LANGUAGES CXX CUDA)

# Tell cmake where to find the template_project
set(template_project_DIR "${DEPENDENCY_ROOT_PREFIX}/install/lib/cmake/template_project")
find_package(template_project REQUIRED)

# Alternatives: 
# 1. find_package(template_project REQUIRED CONFIG PATHS "${DEPENDENCY_ROOT_PREFIX}/install/lib/cmake/")
# 2. When configuring the project: cmake -DCMAKE_PREFIX_PATH=/path/to/template_project_install (...)
# 3. Set CMAKE_PREFIX_PATH in the environment: export CMAKE_PREFIX_PATH=/path/to/template_project_install


# Add executable target
add_executable(${project_name} example_project.cpp)

# Link target
target_link_libraries(${project_name} PRIVATE template_project::template_project)
#target_include_directories(${project_name} PRIVATE ${template_project_INCLUDE_DIRS})

message(WARNING "Note that template_project_INCLUDE_DIRS directories is empty because by default it is not built: ${template_project_INCLUDE_DIRS}\nInstead, includes directly transitions through the linekd target.")
get_target_property(INC template_project::template_project INTERFACE_INCLUDE_DIRECTORIES)
message(STATUS "Include directories: ${INC}\n")
