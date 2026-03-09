# Windows x86_64 MinGW-w64 GCC toolchain defaults.
set(TOOLCHAIN_TRIPLE x86_64-w64-mingw32)
set(TOOLCHAIN_SYSTEM_NAME Windows)
set(TOOLCHAIN_SYSTEM_PROCESSOR x86_64)
set(TOOLCHAIN_RC_TOOL windres)

include("${CMAKE_CURRENT_LIST_DIR}/gcc-cross.cmake")
