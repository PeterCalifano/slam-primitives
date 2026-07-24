set(EXCLUDED_LIST "test_to_exclude")

add_tests(
  ${project_name}
  EXCLUDED_LIST
  TESTS_LIST
  ${CUDA_COMPILE_TARGET}
  CATCH2_TEST_PROPERTIES
  Catch2::Catch2WithMain)

# Link one additional translation unit that includes the public logger header.
# This makes duplicate non-inline definitions fail at link time.
if(TARGET test_CLogger)
  target_sources(
    test_CLogger PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/CLoggerOtherTranslationUnit.cpp")
endif()

set(TESTS_LIST ${TESTS_LIST} PARENT_SCOPE)
