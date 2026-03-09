# Discover and install all header files
file(GLOB installable_headers "*.h" "*.cuh")

# Get the relative path from the root
file(RELATIVE_PATH relative_path_from_root ${CMAKE_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR})

# Remove the 'src/' prefix from the relative path if it exists
string(REPLACE "src/" "" relative_path_without_src ${relative_path_from_root})

# Add src files to library
set(SRC_PATTERN "*.cpp; *.cu")
file(GLOB srcLibFiles_local ${SRC_PATTERN})
file(GLOB srcCudaFilesToPTX_local "*.ptx.cu")

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
set(srcCudaFilesToPTX ${srcCudaFilesToPTX} ${srcCudaFilesToPTX_local} PARENT_SCOPE)

# Install the header files to the relative path
install(FILES ${installable_headers} DESTINATION include/${project_name}/${relative_path_without_src})