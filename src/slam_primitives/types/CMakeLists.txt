# Discover and install all header files
file(GLOB installable_headers "*.h" "*.cuh")

# Preserve the module path beneath the public header prefix.
file(RELATIVE_PATH relative_path_without_src
     "${PROJECT_SOURCE_DIR}/src/slam_primitives"
     "${CMAKE_CURRENT_SOURCE_DIR}")

# Add src files to library
set(SRC_PATTERN "*.cpp; *.cu")
file(GLOB srcLibFiles_local ${SRC_PATTERN})

# Get current folder name
get_filename_component(CURRENT_FOLDER_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
message(STATUS "Library src files found in ${CURRENT_FOLDER_NAME}: ${srcLibFiles_local}")

#################
# User specified subdirectories

# Add subdirectories here
#add_subdirectory(subdir_name)

#################

# Set global # Export list of src files to parent scope
set(srcLibFiles ${srcLibFiles} ${srcLibFiles_local} PARENT_SCOPE)

# Install the header files to the relative path
install(FILES ${installable_headers}
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${project_name}/${relative_path_without_src})
