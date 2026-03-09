# Basic usage of catch2 for build config:
# These tests can use the Catch2-provided main
#add_executable(tests test.cpp)
#target_link_libraries(tests PRIVATE Catch2::Catch2WithMain) 

# These tests need their own main
#add_executable(custom-main-tests test.cpp test-main.cpp)
#target_link_libraries(custom-main-tests PRIVATE Catch2::Catch2)

# Set additional properties for Catch2 test targets
set(CATCH2_TEST_PROPERTIES "--output-on-failure;--reporter=compact") 

# Exclude EXCLUDED_LIST from the list of tests
set(EXCLUDED_LIST "test_to_exclude")  # Specify files to exclude WE
set(TESTS_LIST "") 

# Include the content of the fixtures directory
include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# Add subdirectory 
add_subdirectory(template_test)
add_subdirectory(template_fixtures)

# Add tests to build
add_tests(${project_name} EXCLUDED_LIST TESTS_LIST ${CUDA_COMPILE_TARGET} CATCH2_TEST_PROPERTIES Catch2::Catch2WithMain)

# Make catch2 to search for tests
message(STATUS "List of test targets: ${TESTS_LIST}")
