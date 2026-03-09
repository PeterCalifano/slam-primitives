# Doxygen documentation configuration

# Check if list with subfolders is defined, skip otherwise
if (DEFINED DOC_SUBDIRS AND NOT DOC_SUBDIRS STREQUAL "")
    message(STATUS "Configuring Doxygen documentation...")

    option(BUILD_DOC_HTML   "Enable/Disable doxygen HTML output"  ON)
    option(BUILD_DOC_LATEX  "Enable/Disable doxygen LaTeX output" OFF)

    # Convert booleans to Doxygen YES/NO strings
    if (BUILD_DOC_HTML)
        set(BUILD_DOC_HTML_YN "YES")
    else()
        set(BUILD_DOC_HTML_YN "NO")
    endif()

    if (BUILD_DOC_LATEX)
        set(BUILD_DOC_LATEX_YN "YES")
    else()
        set(BUILD_DOC_LATEX_YN "NO")
    endif()

    # Auto-detect Graphviz dot for call/dependency graphs
    if (DOXYGEN_DOT_FOUND)
        set(DOXYGEN_HAVE_DOT "YES")
        message(STATUS "  Graphviz dot found: call/dependency graphs enabled")
    else()
        set(DOXYGEN_HAVE_DOT "NO")
    endif()

    # Build space-separated input path list from DOC_SUBDIRS
    set(DOXYGEN_INPUT_PATHS "")
    foreach(dir ${DOC_SUBDIRS})
        list(APPEND DOXYGEN_INPUT_PATHS "${dir}")
    endforeach()
    list(APPEND DOXYGEN_INPUT_PATHS "${CMAKE_SOURCE_DIR}/doc")
    string(REPLACE ";" " " DOXYGEN_INPUT_PATHS "${DOXYGEN_INPUT_PATHS}")

    # Generate Doxyfile from template
    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/Doxyfile.in
                   ${CMAKE_CURRENT_BINARY_DIR}/Doxyfile @ONLY)

    # Build documentation target
    add_custom_target(doc
        COMMAND ${DOXYGEN_EXECUTABLE} ${CMAKE_CURRENT_BINARY_DIR}/Doxyfile
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        COMMENT "Generating API documentation with Doxygen" VERBATIM
    )

    # Clean documentation target
    add_custom_target(doc_clean
        COMMAND cmake -E remove_directory ${CMAKE_CURRENT_BINARY_DIR}/html
        COMMAND cmake -E remove_directory ${CMAKE_CURRENT_BINARY_DIR}/latex
        COMMENT "Removing Doxygen documentation"
    )

else()
    message(STATUS "Documentation requested but DOC_SUBDIRS is not defined or empty. Skipping.")
endif()
