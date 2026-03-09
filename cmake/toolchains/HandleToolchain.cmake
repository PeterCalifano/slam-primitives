# This module exposes an interface target with arch/compiler/system defines.

include(CMakeParseArguments)

# Function to handle toolchain settings and create an interface target for build
function(handle_toolchain)

  # Set arguments for the function
  set(oneValueArgs TARGET)
  cmake_parse_arguments(HT "" "TARGET" "" ${ARGN})

  if(NOT HT_TARGET)
    set(HT_TARGET arch_target_settings)
  endif()

  # Add interface target if not specified
  if(NOT TARGET ${HT_TARGET})
    add_library(${HT_TARGET} INTERFACE)
  endif()

  string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _proc)
  
  # Check if the processor matches known architectures and add compile definitions
  if(_proc MATCHES "^(aarch64|arm64)$")
    target_compile_definitions(${HT_TARGET} INTERFACE ARCH_AARCH64=1)
  elseif(_proc MATCHES "^arm")
    target_compile_definitions(${HT_TARGET} INTERFACE ARCH_ARM=1)
  elseif(_proc MATCHES "^(x86_64|amd64)$")
    target_compile_definitions(${HT_TARGET} INTERFACE ARCH_X86_64=1)
  elseif(_proc MATCHES "^(i[3-6]86|x86)$")
    target_compile_definitions(${HT_TARGET} INTERFACE ARCH_X86=1)
  elseif(_proc MATCHES "^riscv64$")
    target_compile_definitions(${HT_TARGET} INTERFACE ARCH_RISCV64=1)
  endif()

  # Define convenience compile definitions
  if(DEFINED CMAKE_SIZEOF_VOID_P)
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
      target_compile_definitions(${HT_TARGET} INTERFACE ARCH_64BIT=1)
    elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
      target_compile_definitions(${HT_TARGET} INTERFACE ARCH_32BIT=1)
    endif()
  endif()

  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_compile_definitions(${HT_TARGET} INTERFACE TARGET_OS_LINUX=1)
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    target_compile_definitions(${HT_TARGET} INTERFACE TARGET_OS_WINDOWS=1)
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    target_compile_definitions(${HT_TARGET} INTERFACE TARGET_OS_MACOS=1)
  endif()

  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_compile_definitions(${HT_TARGET} INTERFACE COMPILER_GNU=1)
  elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_definitions(${HT_TARGET} INTERFACE COMPILER_CLANG=1)
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    target_compile_definitions(${HT_TARGET} INTERFACE COMPILER_MSVC=1)
  endif()

  if(CMAKE_CROSSCOMPILING)
    target_compile_definitions(${HT_TARGET} INTERFACE CROSS_COMPILED=1)
  endif()

  # Export variables for parent scope 
  set(${HT_TARGET}_ARCH "${CMAKE_SYSTEM_PROCESSOR}" PARENT_SCOPE)
  set(${HT_TARGET}_COMPILER "${CMAKE_CXX_COMPILER_ID}" PARENT_SCOPE)
  set(${HT_TARGET}_OS "${CMAKE_SYSTEM_NAME}" PARENT_SCOPE)

endfunction()

# Default interface target for callers that just include this module.
handle_toolchain()
