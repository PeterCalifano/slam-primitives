include("${PROJECT_SOURCE_DIR}/cmake/HandleDoxygenDocs.cmake")

handle_doxygen_docs(
    TARGET_PREFIX "${LIB_NAMESPACE}"
    INPUT_DIRS
        "${PROJECT_SOURCE_DIR}/README.md"
        "${PROJECT_SOURCE_DIR}/src"
        "${PROJECT_SOURCE_DIR}/doc"
    EXCLUDE_DIRS
        "${PROJECT_SOURCE_DIR}/lib"
        "${PROJECT_SOURCE_DIR}/doc/developments"
        "${PROJECT_BINARY_DIR}"
    EXCLUDE_PATTERNS
        "*/lib/*"
        "*/doc/developments/*"
        "*/build*/*"
        "*/_deps/*"
    MAIN_PAGE "${PROJECT_SOURCE_DIR}/doc/main_page.md"
    LAYOUT_FILE "${CMAKE_CURRENT_SOURCE_DIR}/DoxygenLayout.xml"
    DOXYFILE_IN "${CMAKE_CURRENT_SOURCE_DIR}/Doxyfile.in")
