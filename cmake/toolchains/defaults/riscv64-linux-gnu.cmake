# RISC-V 64 Linux GCC toolchain defaults.
set(TOOLCHAIN_TRIPLE riscv64-linux-gnu)
set(TOOLCHAIN_SYSTEM_NAME Linux)
set(TOOLCHAIN_SYSTEM_PROCESSOR riscv64)

include("${CMAKE_CURRENT_LIST_DIR}/gcc-cross.cmake")
