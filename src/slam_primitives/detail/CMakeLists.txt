# Install this header-only module beneath the public package prefix.
file(GLOB installable_headers "*.h")
file(RELATIVE_PATH module_path
     "${PROJECT_SOURCE_DIR}/src/slam_primitives"
     "${CMAKE_CURRENT_SOURCE_DIR}")
install(FILES ${installable_headers}
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${project_name}/${module_path})
