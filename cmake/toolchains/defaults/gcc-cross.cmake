# GCC-style cross toolchain setup. Requires TOOLCHAIN_TRIPLE.
include("${CMAKE_CURRENT_LIST_DIR}/common-cross.cmake")

if(NOT CMAKE_C_COMPILER)
  find_program(CMAKE_C_COMPILER NAMES ${TOOLCHAIN_TRIPLE}-gcc PATHS ${_toolchain_paths})
endif()
if(NOT CMAKE_CXX_COMPILER)
  find_program(CMAKE_CXX_COMPILER NAMES ${TOOLCHAIN_TRIPLE}-g++ PATHS ${_toolchain_paths})
endif()
if(NOT CMAKE_ASM_COMPILER)
  find_program(CMAKE_ASM_COMPILER NAMES ${TOOLCHAIN_TRIPLE}-gcc PATHS ${_toolchain_paths})
endif()
if(NOT CMAKE_AR)
  find_program(CMAKE_AR NAMES ${TOOLCHAIN_TRIPLE}-ar PATHS ${_toolchain_paths})
endif()
if(NOT CMAKE_RANLIB)
  find_program(CMAKE_RANLIB NAMES ${TOOLCHAIN_TRIPLE}-ranlib PATHS ${_toolchain_paths})
endif()
if(NOT CMAKE_STRIP)
  find_program(CMAKE_STRIP NAMES ${TOOLCHAIN_TRIPLE}-strip PATHS ${_toolchain_paths})
endif()

if(NOT CMAKE_C_COMPILER)
  message(FATAL_ERROR "Cross C compiler not found. Expected ${TOOLCHAIN_TRIPLE}-gcc; set TOOLCHAIN_ROOT or adjust PATH.")
endif()
if(NOT CMAKE_CXX_COMPILER)
  message(FATAL_ERROR "Cross CXX compiler not found. Expected ${TOOLCHAIN_TRIPLE}-g++; set TOOLCHAIN_ROOT or adjust PATH.")
endif()

if(TOOLCHAIN_RC_TOOL AND NOT CMAKE_RC_COMPILER)
  find_program(CMAKE_RC_COMPILER
    NAMES ${TOOLCHAIN_TRIPLE}-${TOOLCHAIN_RC_TOOL} ${TOOLCHAIN_RC_TOOL}
    PATHS ${_toolchain_paths}
  )
endif()
