# AArch64 Linux Clang toolchain defaults.
set(TOOLCHAIN_TRIPLE aarch64-linux-gnu)
set(TOOLCHAIN_SYSTEM_NAME Linux)
set(TOOLCHAIN_SYSTEM_PROCESSOR aarch64)

include("${CMAKE_CURRENT_LIST_DIR}/clang-cross.cmake")
