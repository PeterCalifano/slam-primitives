# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

C++ CUDA/OptiX template project (by Pietro Califano) for building GPU-accelerated shared libraries with optional Python/MATLAB bindings. Uses CMake with C++20, Eigen3, and optional CUDA 12+, OptiX, OpenGL, and OpenMP backends.

## Build Commands

**Primary build entry point** is `build_lib.sh`:

```bash
./build_lib.sh                                # Default: RelWithDebInfo, output to ./build
./build_lib.sh -t debug -j 8                  # Debug build, 8 parallel jobs
./build_lib.sh -t release -i                  # Release build + install
./build_lib.sh -N                             # Use Ninja generator
./build_lib.sh --clean                        # Clean rebuild
./build_lib.sh -D ENABLE_CUDA=ON              # Enable CUDA support
./build_lib.sh -r                             # Rebuild only (skip CMake configure)
```

**Running tests** (after build):
```bash
cd build && ctest --output-on-failure
```

**Manual CMake** (if needed):
```bash
cmake -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build -j$(nproc)
```

## Architecture

### Build System (cmake/)

The CMake system is highly modular. Each optional dependency has a dedicated handler module (`Handle*.cmake`) that creates INTERFACE targets with proper namespacing via `LIB_NAMESPACE`. Key modules:

- `HandleGitVersion.cmake` - Extracts semver from git tags, writes VERSION file, populates `config.h`
- `HandleCUDA.cmake` - GPU architecture auto-detection, compiler flags
- `HandleOptiX.cmake` - OptiX SDK integration, PTX compilation pipeline
- `cmake_utils.cmake` - `add_tests()` and `add_examples()` convenience macros
- `cmake_cuda_ptx_tools.cmake` - Compiles `.ptx.cu` files into embedded const char arrays

All optional features default to OFF: `ENABLE_CUDA`, `ENABLE_OPTIX`, `ENABLE_OPENGL`, `ENABLE_TESTS` (ON by default).

### Source Layout

- `src/template_src/` - Core C++ library implementation
- `src/template_src_kernels/` - CUDA kernel code (`.cu`) and PTX kernels (`.ptx.cu`)
- `src/wrapped_impl/` - C wrapper layer for Python/MATLAB bindings
- `src/config.h.in` - CMake-configured header (version macros, feature flags)
- `src/global_includes.h` - Shared utilities (ANSI colors, precision constants)

### Testing

Uses Catch2 (auto-fetched if not found). Tests live in `tests/template_test/`, fixtures in `tests/template_fixtures/`. Test targets are created via the `add_tests()` macro from `cmake_utils.cmake`.

### Consumer Pattern

`examples/template_consumer_project/` demonstrates using this library as an external CMake dependency via `find_package()`. All targets are exported under the `template_project::` namespace.

## Conventions

- Default build type is **RelWithDebInfo** (stricter warnings than Debug)
- Version format: `MAJOR.MINOR.PATCH+<commit_hash>`, derived from git tags matching `v*.*.*`
- File extensions: `.h` for headers, `.cu` for CUDA kernels, `.ptx.cu` for PTX compilation targets
- `ACHTUNG!` prefix in comments marks critical warnings
- Sanitizer builds available via `-DSANITIZE_BUILD=ON`
