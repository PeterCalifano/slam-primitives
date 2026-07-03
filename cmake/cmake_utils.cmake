# CMAKE script containing utility functions for cmake configuration
include_guard(GLOBAL)
if(COMMAND add_examples AND COMMAND add_tests AND COMMAND filter_files_in_list)
    return()
endif()

# Function for entry exclusion in a list based on pattern matching
function(filter_files_in_list input_var output_var exclude_list)
    set(filtered_files "")
    set(exclude_entries ${${exclude_list}})
    foreach(testFile ${${input_var}})
        get_filename_component(fileName ${testFile} NAME)
        get_filename_component(fileNameNoExt ${testFile} NAME_WE)

        list(FIND exclude_entries "${fileName}" index_with_ext)
        list(FIND exclude_entries "${fileNameNoExt}" index_no_ext)
        if(index_with_ext EQUAL -1 AND index_no_ext EQUAL -1)
            list(APPEND filtered_files ${testFile})
        endif()
    endforeach()
    set(${output_var} ${filtered_files} PARENT_SCOPE)
endfunction()

# Function to add examples files to the build
function(add_examples project_lib_name excluded_list target_compile_settings)

    set(EXAMPLES_PATTERN "example_*.cpp; example_*.cu")
    file(GLOB srcExampleFiles RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} ${EXAMPLES_PATTERN})

    # Exclude files in excluded_list (filter_files_in_list is assumed to be a custom macro)
    filter_files_in_list(srcExampleFiles srcExampleFiles ${excluded_list})

    # Get current folder name
    get_filename_component(CURRENT_FOLDER_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
    message(STATUS "Example files found in ${CURRENT_FOLDER_NAME}: ${srcExampleFiles}")

    #message(STATUS "Project linked lib ${project_lib_name} to examples: ${srcExampleFiles}")
    #message(STATUS "Include directories of project lib: ${${project_lib_name}_INCLUDE_DIRS}")

    foreach(exampleFile ${srcExampleFiles})
        get_filename_component(exampleName ${exampleFile} NAME_WE)
        add_executable(${exampleName} ${exampleFile})
        target_link_libraries(${exampleName} PRIVATE ${project_lib_name} ${target_compile_settings})
        target_include_directories(${exampleName} PRIVATE ${${project_lib_name}_INCLUDE_DIRS})
        if(SPDLOG_ENABLED)
            target_compile_definitions(${exampleName} PRIVATE SPDLOG_UTILS_ENABLED=1)
        else()
            target_compile_definitions(${exampleName} PRIVATE SPDLOG_UTILS_ENABLED=0)
        endif()
    endforeach()

endfunction()

function(resolve_python_test_command output_var)
    if(NOT PYTHON_TEST_RUNNER STREQUAL "pytest")
        message(FATAL_ERROR "Unsupported PYTHON_TEST_RUNNER='${PYTHON_TEST_RUNNER}'. The only supported runner is 'pytest'.")
    endif()

    if(NOT "${PYTHON_TEST_CONDA_ENV}" STREQUAL "" AND NOT "${PYTHON_TEST_CONDA_PREFIX}" STREQUAL "")
        message(FATAL_ERROR "Set only one of PYTHON_TEST_CONDA_ENV or PYTHON_TEST_CONDA_PREFIX.")
    endif()

    if(NOT "${PYTHON_TEST_CONDA_ENV}" STREQUAL "" OR NOT "${PYTHON_TEST_CONDA_PREFIX}" STREQUAL "")
        set(pythonTestCondaExecutable "${PYTHON_TEST_CONDA_EXECUTABLE}")
        if(NOT IS_ABSOLUTE "${pythonTestCondaExecutable}")
            find_program(pythonTestCondaExecutableResolved NAMES "${PYTHON_TEST_CONDA_EXECUTABLE}")
            if(pythonTestCondaExecutableResolved)
                set(pythonTestCondaExecutable "${pythonTestCondaExecutableResolved}")
            endif()
        elseif(NOT EXISTS "${pythonTestCondaExecutable}")
            message(FATAL_ERROR "PYTHON_TEST_CONDA_EXECUTABLE does not exist: ${pythonTestCondaExecutable}")
        endif()

        if(NOT pythonTestCondaExecutable)
            message(FATAL_ERROR "Could not find conda executable '${PYTHON_TEST_CONDA_EXECUTABLE}'.")
        endif()

        if(NOT "${PYTHON_TEST_CONDA_PREFIX}" STREQUAL "")
            if(NOT EXISTS "${PYTHON_TEST_CONDA_PREFIX}")
                message(FATAL_ERROR "PYTHON_TEST_CONDA_PREFIX does not exist: ${PYTHON_TEST_CONDA_PREFIX}")
            endif()
            set(pythonTestCommand
                "${pythonTestCondaExecutable}" run -p "${PYTHON_TEST_CONDA_PREFIX}" python)
        else()
            set(pythonTestCommand
                "${pythonTestCondaExecutable}" run -n "${PYTHON_TEST_CONDA_ENV}" python)
        endif()
    else()
        if(NOT "${PYTHON_TEST_EXECUTABLE}" STREQUAL "")
            set(pythonTestCommand "${PYTHON_TEST_EXECUTABLE}")
        else()
            if(DEFINED PROJECT_PYTHON_VERSION AND NOT "${PROJECT_PYTHON_VERSION}" STREQUAL "")
                find_package(Python3 ${PROJECT_PYTHON_VERSION} QUIET COMPONENTS Interpreter)
            else()
                find_package(Python3 QUIET COMPONENTS Interpreter)
            endif()

            if(Python3_FOUND)
                set(pythonTestCommand "${Python3_EXECUTABLE}")
            elseif(DEFINED Python_EXECUTABLE AND NOT "${Python_EXECUTABLE}" STREQUAL "")
                set(pythonTestCommand "${Python_EXECUTABLE}")
            else()
                find_program(pythonTestCommand NAMES python3 python)
            endif()
        endif()

        if(NOT pythonTestCommand)
            message(FATAL_ERROR "Could not resolve a Python executable for pytest tests.")
        endif()
    endif()

    execute_process(
        COMMAND ${pythonTestCommand} -m pytest --version
        RESULT_VARIABLE pythonTestPytestResult
        OUTPUT_VARIABLE pythonTestPytestStdout
        ERROR_VARIABLE pythonTestPytestStderr
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
        TIMEOUT 30)

    if(NOT pythonTestPytestResult EQUAL 0)
        message(FATAL_ERROR
            "pytest is required for Python CTest registration but was not available.\n"
            "Command: ${pythonTestCommand} -m pytest --version\n"
            "stdout:\n${pythonTestPytestStdout}\n"
            "stderr:\n${pythonTestPytestStderr}")
    endif()

    set(${output_var} "${pythonTestCommand}" PARENT_SCOPE)
endfunction()

function(resolve_catch2_test_properties out_var properties_arg)
    set(resolved "")
    if(NOT "${properties_arg}" STREQUAL "")
        if("${properties_arg}" MATCHES ";")
            set(resolved ${properties_arg})
        elseif(DEFINED ${properties_arg})
            set(resolved ${${properties_arg}})
        else()
            set(resolved ${properties_arg})
        endif()
    endif()
    set(${out_var} "${resolved}" PARENT_SCOPE)
endfunction()

function(add_tests project_lib_name excluded_list tests_list_var target_compile_settings catch2_test_properties_var catch2_target)

    file(GLOB srcTestFiles
        RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
        CONFIGURE_DEPENDS
        "test*.cpp"
        "test*.cu")
    filter_files_in_list(srcTestFiles srcTestFiles ${excluded_list})

    file(GLOB srcPythonTestFiles
        RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
        CONFIGURE_DEPENDS
        "test*.py")
    filter_files_in_list(srcPythonTestFiles srcPythonTestFiles ${excluded_list})

    get_filename_component(CURRENT_FOLDER_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
    string(REGEX REPLACE "[^A-Za-z0-9_]" "_" safeCurrentFolderName "${CURRENT_FOLDER_NAME}")
    set(registeredTests ${${tests_list_var}})

    message(STATUS "Compiled test files found in ${CURRENT_FOLDER_NAME}: ${srcTestFiles}")

    if(Catch2_FOUND)
        resolve_catch2_test_properties(catch2TestProperties "${catch2_test_properties_var}")

        set(catch2DiscoverArgs "")
        if(DEFINED CATCH2_TEST_REPORTER AND NOT "${CATCH2_TEST_REPORTER}" STREQUAL "")
            list(APPEND catch2DiscoverArgs REPORTER "${CATCH2_TEST_REPORTER}")
        endif()

        if(catch2TestProperties)
            list(APPEND catch2DiscoverArgs PROPERTIES ${catch2TestProperties})
        endif()

        foreach(testFile ${srcTestFiles})
            get_filename_component(testName ${testFile} NAME_WE)
            add_executable(${testName} ${testFile})

            list(APPEND registeredTests ${testName})

            target_link_libraries(${testName} PRIVATE ${project_lib_name} ${target_compile_settings} ${catch2_target})
            if(SPDLOG_ENABLED)
                target_compile_definitions(${testName} PRIVATE SPDLOG_UTILS_ENABLED=1)
            else()
                target_compile_definitions(${testName} PRIVATE SPDLOG_UTILS_ENABLED=0)
            endif()
            catch_discover_tests(${testName} ${catch2DiscoverArgs})
        endforeach()

    elseif(srcTestFiles)
        message(STATUS "Catch2 not found. Skipping compiled tests in ${CURRENT_FOLDER_NAME}: ${srcTestFiles}")
    endif()

    if(ENABLE_PYTHON_TESTS)
        message(STATUS "Python test files found in ${CURRENT_FOLDER_NAME}: ${srcPythonTestFiles}")

        if(srcPythonTestFiles)
            resolve_python_test_command(pythonTestCommand)
        endif()

        foreach(testFile ${srcPythonTestFiles})
            get_filename_component(testStem ${testFile} NAME_WE)
            set(testName "${safeCurrentFolderName}_${testStem}_py")
            set(testPath "${CMAKE_CURRENT_SOURCE_DIR}/${testFile}")

            add_test(
                NAME ${testName}
                COMMAND
                    ${CMAKE_COMMAND} -E env
                    "PYTHONPATH=${PROJECT_SOURCE_DIR}/python:${PROJECT_BINARY_DIR}/python:$ENV{PYTHONPATH}"
                    "LD_LIBRARY_PATH=${PROJECT_BINARY_DIR}/src:$ENV{LD_LIBRARY_PATH}"
                    ${pythonTestCommand} -m pytest -q "${testPath}")

            set_tests_properties(
                ${testName}
                PROPERTIES
                    LABELS "python;pytest"
                    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
                    TIMEOUT 120)

            list(APPEND registeredTests ${testName})
        endforeach()

    elseif(srcPythonTestFiles)
        message(STATUS "ENABLE_PYTHON_TESTS=OFF. Skipping Python tests in ${CURRENT_FOLDER_NAME}: ${srcPythonTestFiles}")
    endif()

    set(${tests_list_var} "${registeredTests}" PARENT_SCOPE)
endfunction()
