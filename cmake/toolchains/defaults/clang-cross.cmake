# Clang-style cross toolchain setup. Requires TOOLCHAIN_TRIPLE.
include("${CMAKE_CURRENT_LIST_DIR}/common-cross.cmake")

if(NOT CMAKE_C_COMPILER)
  set(CMAKE_C_COMPILER clang)
endif()
if(NOT CMAKE_CXX_COMPILER)
  set(CMAKE_CXX_COMPILER clang++)
endif()

set(CMAKE_C_COMPILER_TARGET ${TOOLCHAIN_TRIPLE})
set(CMAKE_CXX_COMPILER_TARGET ${TOOLCHAIN_TRIPLE})

if(TOOLCHAIN_ROOT AND NOT DEFINED CMAKE_C_COMPILER_EXTERNAL_TOOLCHAIN)
  set(CMAKE_C_COMPILER_EXTERNAL_TOOLCHAIN "${TOOLCHAIN_ROOT}")
endif()

if(NOT CMAKE_AR)
  find_program(CMAKE_AR NAMES llvm-ar ${TOOLCHAIN_TRIPLE}-ar PATHS ${_toolchain_paths})
endif()
if(NOT CMAKE_RANLIB)
  find_program(CMAKE_RANLIB NAMES llvm-ranlib ${TOOLCHAIN_TRIPLE}-ranlib PATHS ${_toolchain_paths})
endif()
if(NOT CMAKE_STRIP)
  find_program(CMAKE_STRIP NAMES llvm-strip ${TOOLCHAIN_TRIPLE}-strip PATHS ${_toolchain_paths})
endif()
