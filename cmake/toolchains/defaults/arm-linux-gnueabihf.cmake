# ARM Linux GCC toolchain defaults.
set(TOOLCHAIN_TRIPLE arm-linux-gnueabihf)
set(TOOLCHAIN_SYSTEM_NAME Linux)
set(TOOLCHAIN_SYSTEM_PROCESSOR arm)

include("${CMAKE_CURRENT_LIST_DIR}/gcc-cross.cmake")
