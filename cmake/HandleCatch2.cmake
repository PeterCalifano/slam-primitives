# CMake configuration to handle Catch2 testing framework
include_guard(GLOBAL)

if (ENABLE_TESTS)
  include(CTest)

  # Initialize configuration for Catch2
  set(_catch2_local_dir "${PROJECT_SOURCE_DIR}/lib/Catch2")

  if(TARGET Catch2::Catch2WithMain OR TARGET Catch2::Catch2)
    set(Catch2_FOUND TRUE)
  else()
    find_package(Catch2 3 QUIET)
  endif()

  # Perform configuration
  if(NOT Catch2_FOUND AND EXISTS "${_catch2_local_dir}/CMakeLists.txt")
    # If catch2 not found or not in lib/ (local dir)
    message(STATUS "Catch2 found in lib/. Adding ${_catch2_local_dir} to the build...")

    # Check targets existence
    if(NOT TARGET Catch2::Catch2WithMain AND NOT TARGET Catch2::Catch2)
      add_subdirectory("${_catch2_local_dir}" "${CMAKE_BINARY_DIR}/_deps/catch2-build")
    endif()
    if(TARGET Catch2::Catch2WithMain OR TARGET Catch2::Catch2)
      set(Catch2_FOUND TRUE)
    endif()
  endif()

  # Fetch if still not found and fetching enabled
  if(NOT Catch2_FOUND AND ENABLE_FETCH_CATCH2)
    message(STATUS "Catch2 not found. Will try to fetch it into lib/ ...")
    # Try to see if git/network are available BEFORE cloning
    find_package(Git QUIET)

    if(NOT Git_FOUND)
      # Git not found, disable tests instead of failing
      message(WARNING "Git not found; cannot fetch Catch2. Tests will be disabled.")
      set(ENABLE_TESTS OFF CACHE BOOL "Build and run tests" FORCE)
    elseif(EXISTS "${_catch2_local_dir}")
      # Local Catch2 directory exists but is not usable
      message(WARNING "Local Catch2 directory exists but is not usable: ${_catch2_local_dir}. Tests will be disabled.")
      set(ENABLE_TESTS OFF CACHE BOOL "Build and run tests" FORCE)
    else()
      # Try fetching it by cloning into lib/

      # Check network access to GitHub
      execute_process(
        COMMAND "${GIT_EXECUTABLE}" ls-remote https://github.com/catchorg/Catch2.git
        RESULT_VARIABLE _git_result
        OUTPUT_QUIET
        ERROR_QUIET
        TIMEOUT 10)

      if(_git_result EQUAL 0)
        # If network access is OK, clone it   
        execute_process(
          COMMAND "${GIT_EXECUTABLE}" clone --depth 1 --branch v3.8.1 https://github.com/catchorg/Catch2.git "${_catch2_local_dir}"
          RESULT_VARIABLE _git_clone_result
          OUTPUT_QUIET
          ERROR_QUIET
          TIMEOUT 300)

        # Check cloning result
        if(_git_clone_result EQUAL 0 AND EXISTS "${_catch2_local_dir}/CMakeLists.txt")
          add_subdirectory("${_catch2_local_dir}" "${CMAKE_BINARY_DIR}/_deps/catch2-build")
          if(TARGET Catch2::Catch2WithMain OR TARGET Catch2::Catch2)
            set(Catch2_FOUND TRUE)
          endif() # All went OK
        else()
          message(WARNING "Failed to clone Catch2 into lib/. Tests will be disabled.") # Fallback to disabling tests
          set(ENABLE_TESTS OFF CACHE BOOL "Build and run tests" FORCE)
        endif()

      else()
        # Network access fails
        message(WARNING "Cannot reach GitHub (no network or blocked). Catch2 not available; tests will be disabled.")
        set(ENABLE_TESTS OFF CACHE BOOL "Build and run tests" FORCE)
      endif()
    endif()
  elseif(NOT Catch2_FOUND AND NOT ENABLE_FETCH_CATCH2)
    message(STATUS "Catch2 not found and ENABLE_FETCH_CATCH2=OFF. Tests will be disabled.")
    set(ENABLE_TESTS OFF CACHE BOOL "Build and run tests" FORCE) # Disable tests since Catch2 not available and auto-fetch not enabled
  endif()

  # Only add tests if we really have Catch2 (either found or fetched)
  if(ENABLE_TESTS AND Catch2_FOUND)
    # Ensure the Catch CMake module is discoverable when Catch2 is a subproject.
    if(DEFINED Catch2_SOURCE_DIR AND EXISTS "${Catch2_SOURCE_DIR}/extras/Catch.cmake")
      list(APPEND CMAKE_MODULE_PATH "${Catch2_SOURCE_DIR}/extras")
    endif()
    include(Catch)
    message(STATUS "Catch2 available: tests will be built.")
    # add_subdirectory(tests) or whatever you do:
    # add_executable(my_tests ...)
    # target_link_libraries(my_tests PRIVATE Catch2::Catch2WithMain)
  else()
    message(STATUS "Tests are disabled (Catch2 not available or ENABLE_TESTS=OFF).")
  endif()
else()
  message(STATUS "Tests are disabled and won't be built (ENABLE_TESTS=OFF).")
endif()
