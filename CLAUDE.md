# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`slam-primitives` is a **header-only C++20 library** providing foundational data structures for Visual-SLAM frontends. It handles keypoint storage, temporal feature tracking, pool-based bundle management, and sliding-window covisibility analysis. Required dependency: Eigen3 (>= 3.4). Optional: CUDA 12+, OptiX, OpenGL, TBB, OpenMP.

## Build Commands

```bash
./build_lib.sh                          # Default: RelWithDebInfo, output to ./build
./build_lib.sh -t debug -j 8            # Debug build, 8 parallel jobs
./build_lib.sh -t release -i            # Release build + install
./build_lib.sh -N                       # Use Ninja generator
./build_lib.sh --clean                  # Clean rebuild
./build_lib.sh -D ENABLE_CUDA=ON        # Enable CUDA support
./build_lib.sh -r                       # Rebuild only (skip CMake configure)
```

**Running tests:**
```bash
cd build && ctest --output-on-failure
ctest --output-on-failure -R <test_name>   # Run a single test by name
```

**Manual CMake:**
```bash
cmake -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build -j$(nproc)
```

## Architecture

### Library Modules (all header-only under `src/slam_primitives/`)

- **types/** — Core type aliases (`SetID`, `FrameID`), C++20 concepts (`FeatureLocation`, `FeatureSetLike`), labeling policies (`SLabelingDisabled`/`SLabelingEnabled<N>`), `SFeatureLocation2D`, `ESetType` enum, `SLidarEnhancedData`
- **feature_sets/** — `CFeatureSet<LocT, MAX_SIZE>`: fixed-capacity ordered keypoint collection for a single frame. `CFeatureTrack<LocT, MAX_LENGTH, LabelPolicyT>`: extends CFeatureSet with temporal frame indexing, manual/auto termination, optional LiDAR data, and configurable labeling
- **bundle/** — `CFeatureSetBundle<SetT, MAX_SLOTS>`: pool allocator for feature sets/tracks with O(1) lookup by SetID via bitset occupancy + unordered_map indexing
- **containers/** — `CCircularBuffer<T, N>`: fixed-capacity ring buffer with O(1) front/back access and iterator support
- **covisibility/** — `CCovisibilityGraph<MAX_FRAMES>`: sliding-window covisibility graph using circular buffer; supports pairwise intersection queries and frame cleanup

All classes use **compile-time capacity templates** for predictable stack allocation and zero-overhead abstraction.

### Test Structure

Tests use Catch2 (auto-fetched if not found) under `tests/`, one test per component:

- `test_types/test_concepts_and_policies.cpp`
- `test_feature_sets/test_CFeatureSet.cpp`, `test_CFeatureTrack.cpp`
- `test_bundle/test_CFeatureSetBundle.cpp`
- `test_containers/test_CCircularBuffer.cpp`
- `test_covisibility/test_CCovisibilityGraph.cpp`
- `test_fixtures/test_fixtures.h` — shared `TestTrack` and `TestBundle` type aliases

Test targets are created via the `add_tests()` macro from `cmake/cmake_utils.cmake`, which discovers `test*.cpp` files in each subdirectory and registers them with Catch2's test discovery.

### Build System (cmake/)

Modular CMake with `Handle*.cmake` modules per dependency, creating INTERFACE targets namespaced via `LIB_NAMESPACE`. The library itself is an INTERFACE target (header-only: no .cpp/.cu sources compiled).

Key CMake options: `ENABLE_CUDA`, `ENABLE_OPTIX`, `ENABLE_OPENGL`, `ENABLE_TBB`, `ENABLE_TESTS` (ON by default), `SANITIZE_BUILD`, `CPU_ENABLE_NATIVE_TUNING` (ON by default for optimized builds).

### Consumer Pattern

`examples/template_consumer_project/` demonstrates using this library via `find_package(slam-primitives)` and linking `slam-primitives::slam-primitives`.

## Conventions

- Default build type is **RelWithDebInfo** (stricter warnings including `-Wconversion`, `-Wnull-dereference`, `-Wfloat-equal`, `-Wnon-virtual-dtor`)
- Version format: `MAJOR.MINOR.PATCH+<commit_hash>`, derived from git tags matching `v*.*.*`
- `ACHTUNG!` prefix in comments marks critical warnings
- Test file naming: `test_<ClassName>.cpp`
- All library code is header-only templates under `src/slam_primitives/`
