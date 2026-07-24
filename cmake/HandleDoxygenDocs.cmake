include_guard(GLOBAL)

function(_doxygen_bool OUT_VAR VALUE)
    # Convert a CMake boolean option to "YES"/"NO" for Doxygen configuration
    if(${VALUE})
        set(${OUT_VAR} "YES" PARENT_SCOPE)
    else()
        set(${OUT_VAR} "NO" PARENT_SCOPE)
    endif()
endfunction()

function(_doxygen_make_path_list OUT_VAR)
    # Convert a list of paths to a space-separated string of absolute paths for Doxygen configuration
    set(_paths)
    foreach(_path IN LISTS ARGN)
        if("${_path}" STREQUAL "")
            continue()
        endif()

        if(IS_ABSOLUTE "${_path}")
            list(APPEND _paths "${_path}")
        else()
            get_filename_component(_abs_path "${_path}" ABSOLUTE BASE_DIR "${PROJECT_SOURCE_DIR}")
            list(APPEND _paths "${_abs_path}")
        endif()

    endforeach()

    string(REPLACE ";" " " _paths_string "${_paths}")
    set(${OUT_VAR} "${_paths_string}" PARENT_SCOPE)

endfunction()

function(handle_doxygen_docs)
    # Set up Doxygen documentation generation for a project
    set(_one_value_args TARGET_PREFIX MAIN_PAGE LAYOUT_FILE DOXYFILE_IN)
    set(_multi_value_args INPUT_DIRS EXCLUDE_DIRS EXCLUDE_PATTERNS)
    cmake_parse_arguments(DOC "" "${_one_value_args}" "${_multi_value_args}" ${ARGN})

    if(NOT DOXYGEN_FOUND)
        message(STATUS "Doxygen not found. Skipping documentation targets.")
        return()
    endif()

    if(NOT DOC_TARGET_PREFIX)
        set(DOC_TARGET_PREFIX "${PROJECT_NAME}")
    endif()

    if(NOT DOC_DOXYFILE_IN)
        set(DOC_DOXYFILE_IN "${CMAKE_CURRENT_SOURCE_DIR}/Doxyfile.in")
    endif()
    if(NOT DOC_MAIN_PAGE)
        set(DOC_MAIN_PAGE "${CMAKE_CURRENT_SOURCE_DIR}/main_page.md")
    endif()
    if(NOT DOC_LAYOUT_FILE)
        set(DOC_LAYOUT_FILE "${CMAKE_CURRENT_SOURCE_DIR}/DoxygenLayout.xml")
    endif()
    if(NOT DOC_INPUT_DIRS)
        set(DOC_INPUT_DIRS "${PROJECT_SOURCE_DIR}/src" "${PROJECT_SOURCE_DIR}/doc")
    endif()

    option(BUILD_DOC_HTML "Enable Doxygen HTML output" ON)
    option(BUILD_DOC_LATEX "Enable Doxygen LaTeX output" OFF)
    option(BUILD_DOC_XML "Enable Doxygen XML output for wrapper docstrings and downstream tooling" OFF)
    option(DOC_WARN_AS_ERROR "Treat Doxygen warnings as errors" OFF)

    _doxygen_bool(BUILD_DOC_HTML_YN BUILD_DOC_HTML)
    _doxygen_bool(BUILD_DOC_LATEX_YN BUILD_DOC_LATEX)
    _doxygen_bool(BUILD_DOC_XML_YN BUILD_DOC_XML)
    _doxygen_bool(DOXYGEN_WARN_AS_ERROR DOC_WARN_AS_ERROR)

    if(DOXYGEN_DOT_FOUND)
        set(DOXYGEN_HAVE_DOT "YES")
        message(STATUS "Graphviz dot found: Doxygen graphs enabled")
    else()
        set(DOXYGEN_HAVE_DOT "NO")
    endif()

    set(_doc_input_dirs ${DOC_INPUT_DIRS})
    if(DOC_MAIN_PAGE)
        list(APPEND _doc_input_dirs "${DOC_MAIN_PAGE}")
        list(REMOVE_DUPLICATES _doc_input_dirs)
    endif()

    _doxygen_make_path_list(DOXYGEN_INPUT_PATHS ${_doc_input_dirs})
    _doxygen_make_path_list(DOXYGEN_EXCLUDE_PATHS ${DOC_EXCLUDE_DIRS})
    string(REPLACE ";" " " DOXYGEN_EXCLUDE_PATTERNS "${DOC_EXCLUDE_PATTERNS}")

    get_filename_component(DOXYGEN_MAIN_PAGE "${DOC_MAIN_PAGE}" ABSOLUTE BASE_DIR "${PROJECT_SOURCE_DIR}")
    get_filename_component(DOXYGEN_LAYOUT_FILE "${DOC_LAYOUT_FILE}" ABSOLUTE BASE_DIR "${PROJECT_SOURCE_DIR}")

    # Set up output directories and configure Doxyfile + namespacing for targets
    set(_doc_binary_dir "${CMAKE_CURRENT_BINARY_DIR}")
    set(_doc_html_dir "${_doc_binary_dir}/html")
    set(_doc_latex_dir "${_doc_binary_dir}/latex")
    set(_doc_xml_dir "${_doc_binary_dir}/xml")
    set(DOXYGEN_TAGFILE "${_doc_html_dir}/${PROJECT_NAME}.tag")

    set(${PROJECT_NAME}_DOXYGEN_HTML_DIR "${_doc_html_dir}" CACHE INTERNAL
        "HTML output directory for ${PROJECT_NAME} Doxygen documentation." FORCE)
    set(${PROJECT_NAME}_DOXYGEN_XML_DIR "${_doc_xml_dir}" CACHE INTERNAL
        "XML output directory for ${PROJECT_NAME} Doxygen documentation." FORCE)
    set(${PROJECT_NAME}_DOXYGEN_DOXYFILE "${_doc_binary_dir}/Doxyfile" CACHE INTERNAL
        "Configured Doxyfile for ${PROJECT_NAME}." FORCE)

    # Configure the Doxyfile with the specified settings
    configure_file("${DOC_DOXYFILE_IN}" "${_doc_binary_dir}/Doxyfile" @ONLY)

    set(_doc_target "${DOC_TARGET_PREFIX}_doc")
    set(_doc_clean_target "${DOC_TARGET_PREFIX}_doc_clean")

    if(NOT TARGET ${_doc_target})
        # Add cmake target to generate Doxygen documentation
        add_custom_target(${_doc_target}
                        COMMAND ${CMAKE_COMMAND} -E make_directory
                            "${_doc_html_dir}" "${_doc_latex_dir}" "${_doc_xml_dir}"
                        COMMAND ${DOXYGEN_EXECUTABLE} "${_doc_binary_dir}/Doxyfile"
                        WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
                        COMMENT "Generating ${PROJECT_NAME} API documentation with Doxygen"
                        VERBATIM)
    endif()

    if(NOT TARGET ${_doc_clean_target})
        # Add custom target to clean generated Doxygen documentation
        add_custom_target(${_doc_clean_target}
                    COMMAND ${CMAKE_COMMAND} -E remove_directory "${_doc_html_dir}"
                    COMMAND ${CMAKE_COMMAND} -E remove_directory "${_doc_latex_dir}"
                    COMMAND ${CMAKE_COMMAND} -E remove_directory "${_doc_xml_dir}"
                    COMMENT "Removing ${PROJECT_NAME} Doxygen documentation"
                    VERBATIM)
    endif()

    # If this is the main project, also add a top-level "doc" and "doc_clean" targets
    if(BUILD_AS_MAIN_PROJECT AND NOT TARGET doc)
        add_custom_target(doc DEPENDS ${_doc_target})
    endif()

    if(BUILD_AS_MAIN_PROJECT AND NOT TARGET doc_clean)
        add_custom_target(doc_clean DEPENDS ${_doc_clean_target})
    endif()
endfunction()
