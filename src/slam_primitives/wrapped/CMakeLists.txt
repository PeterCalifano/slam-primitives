# Discover and install all wrapper facade headers
file(GLOB installable_headers "*.h" "*.cuh")

file(RELATIVE_PATH relative_path_without_src
     "${PROJECT_SOURCE_DIR}/src/slam_primitives"
     "${CMAKE_CURRENT_SOURCE_DIR}")

set(SRC_PATTERN "*.cpp; *.cu")
file(GLOB srcLibFiles_local ${SRC_PATTERN})

get_filename_component(CURRENT_FOLDER_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
message(STATUS "Library src files found in ${CURRENT_FOLDER_NAME}: ${srcLibFiles_local}")

set(srcLibFiles ${srcLibFiles} ${srcLibFiles_local} PARENT_SCOPE)

install(FILES ${installable_headers}
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${project_name}/${relative_path_without_src})
